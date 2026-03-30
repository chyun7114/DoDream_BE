# DoDream_BE

## 성능 테스트 환경

로컬 Docker 기준 단일 서버 환경으로 테스트한다.

- App: `springboot` 1개 컨테이너
- DB: `mysql:8.0`
- Cache: `redis:7`
- Profile: `local` (`application-local.yml`)

리소스 제한(`docker-compose.yml`):

- `springboot`: `1.5 vCPU`, `2GB RAM`
- `mysql`: `1.5 vCPU`, `3GB RAM`
- `redis`: `0.4 vCPU`, `512MB RAM`

포트:

- App: `8080`
- MySQL: `3305 -> 3306`
- Redis: `6378 -> 6379`

## 실행 방법

1. 컨테이너 기동/빌드

```bash
docker compose up -d --build
```

2. 로그 확인

```bash
docker compose logs -f springboot
```

3. 종료

```bash
docker compose down
```

## 성능 시딩 양 (S/M/L)

실행:

```powershell
.\seed\perf\seed.ps1 -Scale S
.\seed\perf\seed.ps1 -Scale M
.\seed\perf\seed.ps1 -Scale L
```

고정 목표 수량:

| Scale | member | job | todo_group | member_recruit_scrap | member_training_scrap |
|---|---:|---:|---:|---:|---:|
| S | 5,000 | 1,000 | 7,500 | 80,000 | 50,000 |
| M | 20,000 | 5,000 | 30,000 | 300,000 | 180,000 |
| L | 50,000 | 10,000 | 75,000 | 900,000 | 500,000 |

`todo` 수량은 분포 규칙(상위 10% saved todo 300~1000, 상위 5% group 80~100) 때문에 자동 계산된다.

- `todo_base_count`: group 분포 기준으로 생성
- `todo_saved_count`: heavy member 분포 기준으로 생성

예시(`Scale=M` 실제 출력):

- `todo_total_count`: `2,145,135`
- `todo_base_count`: `847,456`
- `todo_saved_count`: `1,297,679`

## 참고

- Dockerfile은 멀티스테이지 + Gradle 캐시 레이어를 사용한다.
- 상세 병목 API/시딩/측정 방법: [docs/performance-bottleneck-apis.md](docs/performance-bottleneck-apis.md)
- API별 모니터링 체크리스트: [docs/api-monitoring-checklist.md](docs/api-monitoring-checklist.md)
- 시딩 상세 가이드: [seed/perf/README.md](seed/perf/README.md)
