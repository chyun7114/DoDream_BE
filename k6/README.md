# k6 부하 테스트 가이드 (`GET /v1/todo/other`)

## 1) 테스트 스크립트

- 대상 파일: `k6/todo-other-ramping-arrival.js`
- 실행기: `ramping-arrival-rate`
- 인증 방식: VU별 서로 다른 계정 로그인 후 토큰 사용

기본 부하(현재 기본값):

- `startRate=20`
- `stages: 100 -> 200 -> 400 it/s`
- `preAllocatedVUs=80`
- `maxVUs=500`
- `setup()`에서 토큰 프리워밍 활성화(`ENABLE_TOKEN_PREWARM=true`)
- 본부하 전 워밍업 시나리오 활성화(`ENABLE_WARMUP_SCENARIO=true`, 기본 1분)

## 2) 사전 준비

1. 시딩 완료
   - `.\seed\perf\seed.ps1 -Scale M`
2. 앱/DB/Redis 실행
   - `docker compose up -d --build springboot mysql redis`
3. 모니터링 스택 실행
   - `docker compose --profile monitoring up -d prometheus grafana cadvisor mysqld-exporter`
4. 상태 확인
   - `http://localhost:8080/actuator/prometheus` 응답 확인
   - `http://localhost:9090/targets` 에서 `springboot`, `cadvisor`, `mysqld-exporter` 가 `UP`

## 3) 기본 실행 방법

### PowerShell

```powershell
$env:K6_OUT="experimental-prometheus-rw"
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
k6 run .\k6\todo-other-ramping-arrival.js
```

### Bash

```bash
K6_OUT=experimental-prometheus-rw \
K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
k6 run k6/todo-other-ramping-arrival.js
```

## 4) 더 세게 테스트하는 방법

아래 값만 올리면 동일 스크립트로 강도를 즉시 높일 수 있습니다.

- `STAGE1_TARGET`, `STAGE2_TARGET`, `STAGE3_TARGET`
- `PRE_ALLOCATED_VUS`, `MAX_VUS`
- 필요 시 `USER_COUNT`도 증가

### PowerShell 예시 (강한 부하)

```powershell
$env:K6_OUT="experimental-prometheus-rw"
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:STAGE1_TARGET="200"
$env:STAGE2_TARGET="400"
$env:STAGE3_TARGET="800"
$env:PRE_ALLOCATED_VUS="200"
$env:MAX_VUS="1200"
$env:USER_COUNT="2000"
k6 run .\k6\todo-other-ramping-arrival.js
```

### PowerShell 예시 (프리워밍 + 워밍업 명시)

```powershell
$env:K6_OUT="experimental-prometheus-rw"
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:ENABLE_TOKEN_PREWARM="true"
$env:PREWARM_USER_COUNT="2000"
$env:ENABLE_WARMUP_SCENARIO="true"
$env:WARMUP_DURATION="1m"
$env:WARMUP_RATE="20"
k6 run .\k6\todo-other-ramping-arrival.js
```

## 5) 주요 환경변수

- `BASE_URL` (기본: `http://localhost:8080`)
- `PASSWORD` (기본: `password`)
- `USER_PREFIX` (기본: `seed_user_`)
- `USER_START` (기본: `1`)
- `USER_COUNT` (기본: `1000`)
- `START_RATE` (기본: `20`)
- `STAGE1_TARGET` (기본: `100`)
- `STAGE2_TARGET` (기본: `200`)
- `STAGE3_TARGET` (기본: `400`)
- `PRE_ALLOCATED_VUS` (기본: `80`)
- `MAX_VUS` (기본: `500`)
- `ENABLE_TOKEN_PREWARM` (기본: `true`)
- `PREWARM_USER_COUNT` (기본: `USER_COUNT`)
- `ENABLE_WARMUP_SCENARIO` (기본: `true`)
- `WARMUP_DURATION` (기본: `1m`)
- `WARMUP_RATE` (기본: `20`)
- `WARMUP_PRE_ALLOCATED_VUS` (기본: `20`)
- `WARMUP_MAX_VUS` (기본: `60`)

## 6) 결과 해석 포인트

1. k6 콘솔
   - `http_req_failed` (에러율)
   - `http_req_duration` p95/p99
   - `dropped_iterations` 증가 여부
2. Grafana
   - `k6 RPS`, `k6 p99 Duration`, `k6 Error Rate`
   - `Spring p95`, `App CPU`, `HikariCP pending`
   - `MySQL QPS`, `MySQL Slow Queries/s`, `MySQL Threads`
3. 결론 규칙(권장)
   - 에러율 1% 미만 + p95 안정 + dropped_iterations 거의 없음 => 현재 구간 병목 아님

## 7) 기본 테스트 보고서

- 보고서: [docs/todo-other-baseline-report.md](../docs/todo-other-baseline-report.md)
- 기준 실행일: `2026-03-30`
