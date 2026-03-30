# Performance Seeding

## 목적

`docs/performance-bottleneck-apis.md` 기준의 `S/M/L` 데이터셋을 한 번에 시딩한다.

포함 분포:

- 상위 10% 회원: saved other todo 300~1000개
- todo_group 상위 5%: todo 80~100개
- 나머지 todo_group: todo 20~30개
- todo_group의 70%는 상위 20개 job에 집중
- `todo_group 상위 5%` 검증은 base todo(`other_todo_id = 0`) 기준으로 계산

## 가장 간단한 실행 (PowerShell)

프로젝트 루트에서:

```powershell
.\seed\perf\seed.ps1 -Scale S
.\seed\perf\seed.ps1 -Scale M
.\seed\perf\seed.ps1 -Scale L
```

기본값:

- MySQL container: `dodream-mysql`
- DB: `dodreamdb`
- User: `root`
- Password: `1234`

필요 시 변경:

```powershell
.\seed\perf\seed.ps1 -Scale M -Container dodream-mysql -Database dodreamdb -User root -Password 1234
```

## SQL 직접 실행

```bash
docker exec -i dodream-mysql mysql -uroot -p1234 dodreamdb < seed/perf/run-seed.sql
```

스케일 기본값은 `S`이며, SQL 상단 변수로 변경 가능:

```sql
SET @seed_scale = 'M';
```

## 주의

- 스크립트는 성능 도메인 데이터를 `TRUNCATE`로 초기화한다.
- `region` 테이블은 유지되며, 비어있을 때만 fallback row를 1건 생성한다.
- 회원 비밀번호는 공통 BCrypt 해시(원문 `password`)로 저장된다.
