# `GET /v1/todo/other` 기본 부하 테스트 결과 보고서

## 1) 테스트 개요

- 테스트 일시: `2026-03-30`
- 대상 API: `GET /v1/todo/other`
- 도구: `k6 + Prometheus + Grafana`
- 스크립트: `k6/todo-other-ramping-arrival.js`
- 시나리오: `ramping-arrival-rate`, 최대 `60 it/s` (해당 실행 기준)

## 2) k6 핵심 결과

- `http_req_failed`: `0.00%`
- `todo_other_failed`: `0.00%`
- `todo_other_login_failed`: `0.00%`
- `todo_other_duration p95`: `20.41ms`
- `http_req_duration p95`: `20.56ms`
- `dropped_iterations`: `3` (10분 실행 기준 매우 낮음)
- `iterations`: `21,897`
- `http_reqs`: `21,920`
- `vus_max`: `23`

## 3) Grafana 관측 요약

- `k6 RPS`: 시나리오대로 상승 후 종료 구간에서 하강
- `k6 Error Rate`: 거의 0%
- `Spring p95`: 대체로 `14~20ms` 수준, 종료 시점 일시 스파이크
- `App CPU`: 대체로 `10~18%`, 순간 피크 약 `33%`
- `HikariCP`: `pending=0` 유지, `active`도 낮은 수준
- `MySQL QPS`: 부하 상승에 맞춰 선형 증가
- `MySQL Slow Queries/s`: 0에 가까움
- `MySQL Threads`: `threads_running` 낮은 범위(대체로 2~3)

## 4) 해석

결론적으로 본 실행 구간에서는 병목 징후가 뚜렷하지 않다.

- 에러율 0%
- 지연시간 낮고 안정적
- DB 슬로우쿼리/락 대기 증가 신호 없음
- 커넥션 풀 대기(`pending`) 없음
- CPU/스레드 모두 포화 상태 아님

즉, 현재 부하(최대 60 it/s)에서는 `GET /v1/todo/other`가 안정적으로 처리된다.

## 5) 참고 사항

- 종료 직전의 RPS 급락/지연 스파이크는 종료 구간 및 집계 윈도우 영향 가능성이 높다.
- 대시보드의 일부 단위 표기는 패널 설정 영향으로 실제 값 해석 시 k6 콘솔 결과와 함께 확인한다.

## 6) 다음 단계

포화 지점을 찾기 위해 같은 시나리오를 고부하로 재실행한다.

권장 단계:

1. `100 -> 200 -> 400 it/s`
2. `200 -> 400 -> 800 it/s`
3. 필요 시 `400 -> 800 -> 1200 it/s`

동시에 `dropped_iterations`, `p95/p99`, `Hikari pending`, `MySQL Slow Queries/s`를 우선 추적한다.

## 7) 고부하 재측정 결과 (프리워밍/워밍업 적용)

- 측정 일시: `2026-03-31`
- 실행 조건:
  - `ENABLE_TOKEN_PREWARM=true`
  - `PREWARM_USER_COUNT=2000`
  - `ENABLE_WARMUP_SCENARIO=true` (`1m`, `20 it/s`)
  - 본 부하: `100 -> 200 -> 400 it/s` (10m)

### k6 결과 요약

- `todo_other_duration p95`: `2.53s` (임계치 700ms 실패)
- `http_req_failed`: `0.00%`
- `dropped_iterations`: `16,548`
- 경고: `Insufficient VUs, reached 500 active VUs`
- `http_reqs`: `109,852` (평균 `153.35 req/s`)

### Grafana 관측 요약

- `k6 RPS`: 약 `230~250 req/s` 구간에서 평탄(목표 대비 상승 정체)
- `Spring p95`: 약 `1.7~2.0s` 고착
- `Hikari pending`: 약 `180` 수준으로 장시간 유지
- `App CPU`: 약 `50~60%` 구간
- `MySQL QPS`: 약 `4.8k~5k ops/s` 부근 plateau
- `MySQL Slow Queries/s`: 유의미한 증가 없음

### 해석 및 결론

- 프리워밍/워밍업 이후에도 고부하 구간에서 지연이 급상승하므로, 초반 로그인 버스트만의 문제는 아님.
- 에러율은 0%지만 `Hikari pending`과 `Spring p95`가 함께 상승해 **커넥션 풀 대기 기반 병목**이 발생.
- 현재 구성에서 `/v1/todo/other`의 안정 처리 한계는 대략 `200~250 RPS` 구간으로 판단.

### 후속 조치 우선순위

1. `/v1/todo/other` 반복 조회 쿼리(N+1 성격) 축소/통합
2. 인덱스 점검 및 실행계획(`EXPLAIN`) 기반 튜닝
3. HikariCP(`maximumPoolSize`, `connectionTimeout`) 조정
4. 동일 시나리오로 `100/150/200/250/300 RPS` 단계 테스트해 임계점 정밀 측정
