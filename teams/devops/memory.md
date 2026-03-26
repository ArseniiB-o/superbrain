# Team Memory: devops
Last updated: 2026-03-26

## Accumulated Knowledge
- Docker: always use non-root user in containers
- Never use :latest tags in production — pin versions
- Secrets: use env vars or secrets manager, never bake into images
- CI/CD: always run tests before deploy, have rollback strategy
- Health checks: liveness + readiness probes required in Kubernetes
- Monitoring: Prometheus metrics + Grafana dashboards minimum
