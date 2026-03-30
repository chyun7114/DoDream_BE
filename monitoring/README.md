# Monitoring Stack (Prometheus + Grafana)

## 1) Start app/database stack

```bash
docker compose up -d --build springboot mysql redis
```

## 2) Start monitoring stack

```bash
docker compose --profile monitoring up -d prometheus grafana cadvisor mysqld-exporter
```

Access:

- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3001` (`admin` / `admin`)
- cAdvisor raw metrics: `http://localhost:8081/metrics`

If `mysqld-exporter` fails, recreate it after config changes:

```bash
docker compose --profile monitoring up -d --force-recreate mysqld-exporter
docker compose logs -f mysqld-exporter
```

Grafana dashboard is auto-provisioned:

- `DoDream - Todo Other Performance`

## 3) Metric checks

- Spring metrics: `http://localhost:8080/actuator/prometheus`
- Prometheus targets: `http://localhost:9090/targets`
