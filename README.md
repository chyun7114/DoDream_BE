# DoDream_BE

## Docker 실행 (단일 서버 기준)

1. 애플리케이션 jar 빌드
```bash
./gradlew bootJar
```

2. 컨테이너 기동
```bash
docker compose up -d --build
```

3. 로그 확인
```bash
docker compose logs -f springboot
```

4. 종료
```bash
docker compose down
```
