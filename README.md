# DoDream_BE

## 성능 테스트 기준 환경

로컬 Docker 환경에서 아래 구성으로 성능 테스트를 진행한다.

- App: `springboot` 1개 컨테이너 (단일 서버 가정)
- DB: `mysql:8.0`
- Cache: `redis:7`
- Profile: `local` (`application-local.yml`)
- Orchestration: `docker compose`

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

## Docker 빌드 전략

- `Dockerfile`은 멀티스테이지 빌드 사용
- 앱 실행 전 `bootJar`를 로컬에서 미리 실행할 필요 없음
- Gradle 캐시 마운트(`--mount=type=cache,target=/root/.gradle`)로 의존성/빌드 캐시 재사용
- `.dockerignore`로 불필요한 빌드 컨텍스트 제외

## 참고

- 상세 병목 API/시딩/측정 방법: [docs/performance-bottleneck-apis.md](docs/performance-bottleneck-apis.md)
