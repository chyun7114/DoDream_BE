# k6 Load Test - `/v1/todo/other`

## Script

- `k6/todo-other-ramping-arrival.js`

Scenario (from docs):

- `ramping-arrival-rate` 5 -> 60 rps (10 minutes)
- VU: `preAllocated=20`, `maxVUs=120`
- Threshold:
  - `p(95) < 700ms`
  - `failed < 1%`

## Prerequisites

- Seeded user exists (`seed_user_1` / `password`)
- App is running at `http://localhost:8080`
- Prometheus remote write receiver enabled (`http://localhost:9090/api/v1/write`)

## Run with Prometheus remote write

```bash
K6_OUT=experimental-prometheus-rw \
K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write \
k6 run k6/todo-other-ramping-arrival.js
```

PowerShell:

```powershell
$env:K6_OUT="experimental-prometheus-rw"
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
k6 run .\k6\todo-other-ramping-arrival.js
```

Optional env:

- `BASE_URL` (default: `http://localhost:8080`)
- `LOGIN_ID` (default: `seed_user_1`)
- `PASSWORD` (default: `password`)
