# 성능 병목 API 분석 및 부하테스트 시나리오

## 문서 목적

본 문서는 DoDream_BE의 병목 가능 API를 사전 식별하고, 부하테스트(k6) 설계를 위한 기준을 제공한다.

## 코드 정합성 검증 결과

- 기존 문서의 병목 API 선정은 전반적으로 타당하다.
- `TodoService`의 `/v1/todo/other*`, `/v1/todo/other/{jobId}`는 그룹별 반복 조회(`findTopNByTodoGroup` + `countByTodoGroup`)가 실제로 존재한다.
- `GET /v1/community/todos`는 로그인 사용자의 `mySavedTodoIds`를 먼저 조회하고, 메인 조회 select 절에서 `todo.id.in(mySavedTodoIds)`를 계산한다. 즉, `WHERE IN` 필터라기보다 저장 여부 계산 비용과 대형 id 리스트 전달 비용이 병목 포인트다.
- `POST /v1/job/recommend`는 요청마다 `jobRepository.findAll()` + 외부 Clova 호출 + 추천 결과 개수만큼 `findByJobName`을 수행한다.
- `GET /v1/recruit/popular`는 요청 1회당 외부 채용 API count 호출을 최대 3회 수행하며, fallback 시 `jobRepository.findAll()`도 추가된다.
- `GET /v1/training/list`, `GET /v1/recruit/list`는 실제로 TTL 15분(`CustomCacheableWithLock(ttl = 15)`) 캐시를 사용한다. 콜드키에서는 외부 API 지연 영향이 크다.

## 병목 API 목록

| 병목 API                                                        | 병목 이유                                                                                           | 테스트 지점                                            | k6 기준 시나리오                                                            |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------- |
| `GET /v1/todo/other`                                            | TodoGroup 목록 조회 후 그룹별 `findTop2ByTodoGroup` + `countByTodoGroup` 반복(사실상 2N+고정쿼리).  | DB 쿼리 수/요청, p95, DB CPU, 커넥션 풀 점유율         | `ramping-arrival-rate` 5→60 rps(10m), VU 20~120, `p(95)<700ms`, `failed<1%` |
| `GET /v1/todo/other/public`                                     | 상위 3개 그룹에 대해 그룹별 추가 조회 2회씩 고정 발생(요청당 고정 쿼리 다수).                       | 반복 호출 p95, active session, 캐시 유무 비교          | `constant-arrival-rate` 30 rps(8m), VU 50~100, `p(95)<500ms`, `failed<1%`   |
| `GET /v1/todo/other/simple/{todoGroupId}`                       | 유사 그룹 조회 후 그룹별 todo/count 반복 조회.                                                      | hot/cold `todoGroupId`별 편차, 쿼리 수                 | `per-vu-iterations` 50vu x 100iter, 랜덤 id, `p(95)<800ms`                  |
| `GET /v1/todo/other/{jobId}`                                    | 페이지 결과(최대 10건) 각 row마다 `top3 todo + count` 추가 조회.                                    | page=0/1/5/10 비교, p99                                | `ramping-vus` 0→80(3m) 유지 10m, `p(95)<900ms`, `p(99)<1500ms`              |
| `GET /v1/todo/{todoGroupId}`                                    | 내 todo 목록과 상대 목록 비교 시 `anyMatch`로 O(M×N) CPU 비용 발생.                                 | todo 수 구간(10/100/300)별 앱 CPU/GC                   | `constant-vus` 40 vus(10m), `p(95)<700ms`, `failed<1%`                      |
| `GET /v1/community/todos`                                       | 로그인 사용자는 `findMyTodoIds` 선조회 + 대형 id 리스트 기반 저장여부 계산(`todo.id.in(...)`) 수행. | saved 개수(0/100/1000)별 p95, heap, DB plan            | `ramping-arrival-rate` 10→80 rps(12m), 로그인/비로그인 7:3, `p(95)<850ms`   |
| `POST /v1/job/recommend`                                        | `findAll()` + 외부 LLM + 추천 건수만큼 DB 재조회 반복으로 DB/외부API 복합 병목.                     | 외부 API latency 분리, timeout, 앱 스레드 점유         | `constant-arrival-rate` 5 rps(10m), VU 20~60, `p(95)<2500ms`, `failed<2%`   |
| `GET /v1/recruit/popular`                                       | 인기 직업 최대 3개 각각 외부 채용 count 호출(요청당 다중 외부 호출).                                | 외부 호출 횟수/요청, 웜/콜드 캐시, p95                 | `ramping-arrival-rate` 2→20 rps(10m), `p(95)<1800ms`, `failed<2%`           |
| `GET /v1/job/add`                                               | 페이징 없이 `jobRepository.findAll()` 전체 조회.                                                    | row 수(1k/10k/50k)별 응답시간, 힙                      | `constant-vus` 20 vus(6m), `p(95)<600ms`, `failed<1%`                       |
| `GET /v1/training/list`, `GET /v1/recruit/list`                 | 외부 API 의존. 캐시 TTL 15분이지만 파라미터 분산/콜드키에서 지연 급증 가능.                         | cache hit ratio, 외부 latency, timeout/에러율          | 웜캐시 30 rps + 콜드캐시 15 rps 각 10m, `p(95)<1200ms`                      |
| `POST /v1/scrap/recruit/{recruitId}`, `POST /v1/scrap/training` | 저장 전 중복/개수 체크 + 외부 detail API 호출 + 쓰기 트랜잭션.                                      | TPS 증가 시 write latency, 외부 detail latency, 실패율 | `ramping-vus` 0→50(4m) 유지 8m, `p(95)<1000ms`, `failed<1.5%`               |

## 테스트 지점별 분석 방법 (Grafana 기준)

실행 원칙:
- 모든 그래프는 같은 시간축으로 정렬해서 본다: `k6 -> app -> db -> redis/외부 API` 순서로 상관관계 확인
- 한 번에 하나의 변수만 변경한다: `RPS`, `데이터량(S/M/L)`, `로그인 비율`, `콜드/웜 캐시`
- 임계치 초과 시 즉시 원인 분류 태그를 남긴다: `DB`, `APP_CPU`, `GC`, `EXTERNAL_API`, `CACHE_MISS`

추천 대시보드 구성:
- `K6 Overview`: `RPS`, `http_req_duration p50/p95/p99`, `http_req_failed`, `iteration_duration`
- `Spring/JVM`: `CPU`, `heap used`, `GC pause`, `thread count`, `http server requests by uri`
- `DB(MySQL)`: `CPU`, `QPS`, `active connections`, `slow query count`, `rows examined/sent`
- `Redis`: `ops/sec`, `hit ratio`, `used memory`, `evicted keys`
- `External API`: `호출 건수`, `외부 응답 p95`, `timeout`, `5xx 비율`

지점별로 보는 그래프와 판정 기준:

| 테스트 지점 | Grafana에서 볼 그래프 | 병목 판정 포인트 |
|---|---|---|
| DB 쿼리 수/요청 | `DB QPS`, `RPS`, `rows examined` | RPS는 고정인데 QPS가 같이 선형 증가하면 N+1/과조회 의심 |
| p95/p99 응답시간 | `http_req_duration p95/p99`, `uri별 요청시간` | p50 안정 + p95/p99만 급등하면 일부 요청(특정 파라미터/콜드키) 병목 |
| DB CPU | `mysql cpu %`, `innodb row ops` | 앱 CPU 낮고 DB CPU만 80%+ 지속이면 DB 중심 병목 |
| DB active session/connection pool | `active connections`, `hikaricp active/pending` | pending 증가 + 응답지연 동반 시 커넥션 풀 고갈 |
| 앱 CPU/GC | `process cpu`, `jvm gc pause`, `heap used` | GC pause 급증 + 응답지연 동반 시 객체 생성/직렬화 부담 |
| hot/cold ID 편차 | `uri+path variable별 latency 분포` | 특정 id 구간만 p95 급등하면 데이터 분포/인덱스/캐시 편향 문제 |
| page 파라미터 편차 | `page 값별 latency`, `response size` | page 증가에 비례해 지연 증가하면 페이징 후처리 비용 의심 |
| 로그인/비로그인 차이 | `auth 여부 태그별 p95`, `DB rows examined` | 로그인 요청만 느리면 `mySavedTodoIds` 관련 계산 비용 가능성 큼 |
| 외부 API latency 분리 | `외부 호출 p95`, `timeout`, `app endpoint p95` | 외부 p95와 앱 p95가 동행 상승하면 외부 의존 병목 |
| 캐시 효과(웜/콜드) | `redis hit ratio`, `외부 호출 건수`, `endpoint p95` | hit ratio 하락 시 외부 호출 증가 + p95 상승이면 캐시 미스 영향 |
| 쓰기 TPS/락 경합 | `POST TPS`, `DB write latency`, `lock wait`, `error rate` | TPS 임계점에서 lock wait/실패율 동시 증가하면 쓰기 경합 |

API별 분석 체크리스트:
1. `/v1/todo/other*`, `/v1/todo/other/{jobId}`: `RPS 대비 DB QPS 증가율`, `hikaricp pending` 우선 확인
2. `/v1/todo/{todoGroupId}`: `app CPU`, `GC pause`, `todo 개수 구간별 p95` 비교
3. `/v1/community/todos`: `로그인/비로그인 분리 p95`, `rows examined`, `heap` 확인
4. `/v1/job/recommend`: `외부 Clova p95`와 `endpoint p95` 상관관계 먼저 확인 후 DB 조회량 확인
5. `/v1/recruit/popular`, `/v1/training/list`, `/v1/recruit/list`: `cache hit ratio`와 `외부 호출 건수`를 같이 확인
6. `scrap 저장 API`: `POST TPS 대비 write latency`, `error rate`, `lock wait` 확인

테스트 종료 후 기록 포맷(권장):
- `시나리오`: 예) `todo_other_M_dataset_60rps_10m`
- `결과`: `p95`, `error`, `RPS`
- `병목 위치`: `DB` / `APP` / `EXTERNAL` / `CACHE`
- `근거 그래프`: 대시보드 이름 + 패널명 2~3개
- `다음 액션`: 인덱스 추가, 쿼리 튜닝, 캐시 키 전략 조정 등

## 부하테스트용 초기 시딩 데이터 권장량

아래 수치는 병목이 실제로 드러나는 최소 규모 기준이다. 1회성 스모크 테스트는 `S`, 본격 튜닝/회귀는 `M` 이상 권장.

| 구간            | member |    job | todo_group |      todo | member_recruit_scrap | member_training_scrap | 비고                |
| --------------- | -----: | -----: | ---------: | --------: | -------------------: | --------------------: | ------------------- |
| `S` (빠른 재현) |  5,000 |  1,000 |      7,500 |   150,000 |               80,000 |                50,000 | PR/기능검증 단계    |
| `M` (권장 기준) | 20,000 |  5,000 |     30,000 |   700,000 |              300,000 |               180,000 | 병목 분석/튜닝 기준 |
| `L` (한계 검증) | 50,000 | 10,000 |     75,000 | 1,800,000 |              900,000 |               500,000 | 캐시 미스/피크 검증 |

추가로 반드시 넣을 분포:

- 상위 10% 회원은 `saved other todo`를 300~1000개 보유(community API 재현용).
- 인기 직업 상위 20개에 `todo_group`가 집중되도록 스큐 분포 적용(실서비스 트래픽 유사).
- `todo_group`당 `todo`는 평균 20~30개, 상위 5%는 80개 이상(상세 API CPU/직렬화 비용 재현).

## 시딩 방식 가이드 (코드 꼭 짜야 하나?)

결론:
- 처음부터 Java 시더 코드를 새로 짤 필요는 없다.
- 1차는 SQL 배치 시딩으로 시작하고, 반복 실행/리셋 자동화가 필요해질 때만 코드 시더를 추가한다.

권장 순서:
1. 정적 기준 데이터는 기존 `data.sql` 유지
2. 대용량 성능 데이터는 별도 SQL 파일로 분리 (`seed/perf/01_member.sql`, `02_todo.sql`, `03_scrap.sql`)
3. MySQL에서 `INSERT ... SELECT`, 숫자 시퀀스 테이블(또는 재귀 CTE)로 대량 생성
4. 분포(상위 10% heavy user, 인기 job 쏠림)는 SQL에서 가중치 컬럼으로 반영
5. 시딩 완료 후 `ANALYZE TABLE` 수행, 건수 검증 쿼리로 확인

최소 자동화(코드 없이):
- `seed/perf/run-seed.sql` 하나로 `TRUNCATE -> INSERT -> 검증 SELECT`까지 실행
- 실행 예: `docker exec mysql mysql -udodream -pdodream2025 dodreamdb < /seed/perf/run-seed.sql`

코드 시더가 필요한 시점:
- 데이터 패턴을 자주 바꿔야 할 때
- 테스트마다 seed 버전을 관리해야 할 때
- CI에서 시딩을 자동 수행해야 할 때

그때는:
- 현재 레포의 `DummyDataInitializer` 방식처럼 `JdbcTemplate batchUpdate` 기반으로 `@Profile(\"perf-seed\")` 전용 시더를 두는 것을 권장
- 배치 크기(`BATCH_SIZE`), 커밋 단위, 재실행 가능(idempotent) 조건만 지키면 충분

## AWS 유사 도커 제한 가이드 (로컬 부하테스트용)

현재 레포의 `docker-compose-main.yml`에는 자원 제한이 없다. 아래처럼 제한을 주고 테스트하면 AWS 단일 인스턴스 환경과 더 유사해진다.

권장 기준(단일 서버/단일 앱 컨테이너 기준):

- 호스트 총량 목표: `4 vCPU / 8GB RAM`
- `springboot`: `1.5 CPU / 2GB RAM`
- `mysql`: `1.5 CPU / 3GB RAM`
- `redis`: `0.4 CPU / 512MB RAM`
- 여유분(OS/모니터링/k6): 약 `0.6 CPU / 2.5GB RAM`

`docker-compose-main.yml` 예시(핵심만):

```yaml
services:
  springboot:
    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 2G
    environment:
      - JAVA_TOOL_OPTIONS=-XX:+UseContainerSupport -Xms1024m -Xmx1536m

  mysql:
    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 3G

  redis:
    deploy:
      resources:
        limits:
          cpus: "0.4"
          memory: 512M
```

주의:

- docker compose(non-swarm) 환경에서는 `deploy.resources`가 무시될 수 있으므로, 필요 시 `mem_limit`, `cpus` 옵션을 함께 사용.
- 단일 앱 컨테이너 기준으로만 부하를 주고, 배포 전후 비교는 동일 리소스 제한에서 반복 실행해 편차를 줄인다.
- 외부 API(사람인/Work24/Clova)는 실제 호출보다 스텁/리플레이도 병행해 내부 병목과 외부 지연을 분리 측정.

## 공통 부하테스트 기준

- 테스트 시간: 최소 10분(워밍업 2분 + 측정 8분)
- 성공 기준: API별 threshold 충족 + 오류율 유지
- 필수 수집 지표: `http_req_duration`, `http_req_failed`, RPS, DB QPS, DB CPU, active connection, GC, 외부 API latency
- 데이터셋 원칙: `S/M/L` 3구간 동일 시나리오 반복

## 우선 실행 순서

1. `/v1/todo/other*`, `/v1/todo/{todoGroupId}`
2. `/v1/community/todos`
3. `/v1/job/recommend`
4. `/v1/recruit/popular`
5. `/v1/job/add`
6. 외부 API 의존군(`/v1/training/list`, `/v1/recruit/list`, scrap 저장 API)
