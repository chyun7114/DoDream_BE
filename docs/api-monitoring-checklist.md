# API별 모니터링 체크리스트

## 목적

부하테스트 중 Grafana/Prometheus에서 API별로 무엇을 우선 확인할지 빠르게 판단하기 위한 운영 체크리스트다.

기준 문서:
- [성능 병목 API 분석 및 부하테스트 시나리오](C:\Users\user\Desktop\coding\DoDream!\DoDream_BE\docs\performance-bottleneck-apis.md)

공통 대시보드(권장):
- `DoDream - Todo Other Performance` (현재 `/v1/todo/other`용)
- Prometheus 기본 조회 (`http://localhost:9090`)

공통 우선순위:
1. 에러율(`failed`) 급증 여부
2. p95/p99 지연 상승 여부
3. DB(QPS/CPU/threads)와 앱(CPU/GC/Hikari) 중 어디가 먼저 치솟는지
4. 외부 API/캐시 영향 분리

부하테스트 계정 원칙:
- 단일 계정 토큰 공유 방식 금지
- VU별 서로 다른 계정으로 로그인 후 토큰 사용(유저 분산)
- 신규 API k6 스크립트 작성 시 동일 규칙 적용

## 1) GET /v1/todo/other

핵심 병목 가설:
- 그룹별 `findTop2 + count` 반복 조회로 DB 쿼리량 증가

반드시 볼 지표:
- k6: `RPS`, `p95`, `error rate`
- App: `http_server_requests_seconds`(uri=`/v1/todo/other`), `hikaricp_connections_pending`
- DB: `mysql qps`, `mysql cpu`, `threads_running`

병목 판정:
- RPS 상승과 함께 `mysql qps`가 선형 상승 + `hikaricp pending` 증가 => DB 조회 병목 가능성 높음
- p95만 급등하고 p50 안정 => 일부 요청/일부 데이터셋 편중 가능성

## 2) GET /v1/todo/other/public

핵심 병목 가설:
- 고정 3그룹 대상이지만 요청당 다중 쿼리 발생

반드시 볼 지표:
- `p95`, `mysql qps`, `threads_running`
- 동일 파라미터 반복 시 응답시간 분산

병목 판정:
- 트래픽 증가 대비 지연이 비선형으로 증가하면 DB 동시성 한계 가능성

## 3) GET /v1/todo/other/simple/{todoGroupId}

핵심 병목 가설:
- `todoGroupId` hot/cold에 따른 편차

반드시 볼 지표:
- 요청 태그별(pseudo group) p95 분포
- DB rows/queries 변화

병목 판정:
- 특정 ID 구간에서만 p95 급등 => 데이터 스큐/접근 패턴 문제

## 4) GET /v1/todo/other/{jobId}

핵심 병목 가설:
- 페이지 결과 row마다 추가 조회 반복

반드시 볼 지표:
- `page`별 p95/p99
- 응답 크기 대비 지연

병목 판정:
- page 증가에 비례해 p95/p99 상승 => 후처리/추가 조회 비용 누적

## 5) GET /v1/todo/{todoGroupId}

핵심 병목 가설:
- O(M×N) 비교 로직으로 앱 CPU/GC 부담

반드시 볼 지표:
- App CPU, heap 사용량, GC pause
- 데이터 구간별(10/100/300) p95

병목 판정:
- DB 지표 안정 + App CPU/GC만 급등 => 애플리케이션 계산 병목

## 6) GET /v1/community/todos

핵심 병목 가설:
- 로그인 사용자 `mySavedTodoIds` 기반 계산 비용 증가

반드시 볼 지표:
- 로그인/비로그인 분리 p95
- heap/GC, DB rows examined

병목 판정:
- 로그인 트래픽에서만 p95/heap 상승 => saved id 계산/전달 비용 영향

## 7) POST /v1/job/recommend

핵심 병목 가설:
- DB 전체 조회 + 외부 LLM 호출 + 후속 DB 조회 반복

반드시 볼 지표:
- 외부 API p95, timeout, 앱 endpoint p95
- DB qps

병목 판정:
- 외부 p95와 앱 p95가 동시 상승 => 외부 의존 병목 우선
- 외부 안정인데 앱/DB만 상승 => 내부 처리 병목

## 8) GET /v1/recruit/popular

핵심 병목 가설:
- 요청당 외부 채용 API 다중 호출

반드시 볼 지표:
- 외부 호출 건수/요청
- endpoint p95, failed rate

병목 판정:
- 호출 건수 증가와 p95 동행 => fan-out 외부 호출 영향

## 9) GET /v1/job/add

핵심 병목 가설:
- 페이징 없는 `findAll`로 데이터량에 선형 증가

반드시 볼 지표:
- row 수 구간별 p95
- 앱 heap, GC, DB qps

병목 판정:
- row 수 증가에 따라 응답시간/heap이 함께 증가 => 전체 조회 병목

## 10) GET /v1/training/list, GET /v1/recruit/list

핵심 병목 가설:
- 외부 API + 캐시 히트율 의존

반드시 볼 지표:
- Redis hit ratio, 외부 호출 건수
- 콜드/웜 시나리오별 p95

병목 판정:
- hit ratio 하락 + 외부 호출 증가 + p95 상승 => 캐시 미스 중심 병목

## 11) POST /v1/scrap/recruit/{recruitId}, POST /v1/scrap/training

핵심 병목 가설:
- 중복검사 + 외부 detail + 쓰기 트랜잭션

반드시 볼 지표:
- POST TPS, write latency, error rate
- DB lock wait(가능 시), threads_running

병목 판정:
- TPS 임계 구간에서 실패율/지연 급증 => 쓰기 경합 또는 외부 detail 지연

## 테스트 종료 기록 템플릿

- 시나리오: `todo_other_M_60rps_10m`
- 결과: `p95`, `p99`, `failed`, `avg RPS`
- 병목 위치: `DB` / `APP` / `CACHE` / `EXTERNAL`
- 근거 지표: 패널명 2~3개
- 액션 아이템: 인덱스/쿼리/캐시/코드 최적화 중 무엇을 할지
