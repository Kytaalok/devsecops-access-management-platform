# DevSecOps Access Management Platform

Репозиторий практической части ВКР:
«Система централизованного управления пользователями и ролями в DevSecOps-инфраструктуре».

Проект демонстрирует централизованную аутентификацию через Keycloak, сопоставление ролей с прикладным и Kubernetes RBAC, декларативный CI/CD-конвейер Jenkins и сбор доказательных артефактов тестирования.

## Состав проекта

```text
.
├── Jenkinsfile                 # CI/CD pipeline: tests, security gates, build, push, deploy, smoke
├── docker-compose.yaml         # локальный запуск базовых компонентов
├── docs/                       # материалы ВКР: приложения, тест-план, протоколы и артефакты
├── infra/                      # Kubernetes, Jenkins, monitoring и bootstrap/smoke scripts
├── services/                   # Task Manager API и frontend
└── tools/                      # вспомогательные maintenance-скрипты
```

## Основные компоненты

- `services/task-manager-api` - FastAPI-приложение с проверкой JWT, бизнес-RBAC и pytest-тестами.
- `services/task-manager-frontend` - Nginx frontend для демонстрации ролей и работы с Task Manager API.
- `infra/k3s/base` - Kustomize base для API, frontend, PostgreSQL, Keycloak, Ingress и RBAC.
- `infra/k3s/jenkins` - Helm/JCasC-конфигурация Jenkins и связанные Kubernetes-ресурсы.
- `infra/k3s/monitoring` - Prometheus, Loki, Grafana, datasource и dashboard security events.
- `infra/scripts` - bootstrap Keycloak, smoke-тесты, генерация тестовых пользователей, установка monitoring/Loki.
- `docs/testing` - методика и протокол тестирования.
- `docs/testing/artifacts` - переносимые отчёты тестов, например `api-pytest.xml`.
- `docs/appendices` - приложения к ВКР: манифесты, Jenkinsfile, JCasC, smoke-script, Grafana, logs.

## Быстрый запуск API-тестов

```bash
cd services/task-manager-api
python -m pip install --no-cache-dir -r requirements.txt
PYTHONPATH="$PWD" python -m pytest -q
```

JUnit-отчёт для Jenkins/документации можно сформировать так:

```bash
mkdir -p ../../docs/testing/artifacts
PYTHONPATH="$PWD" python -m pytest -q --junitxml=../../docs/testing/artifacts/api-pytest.xml
```

## Развёртывание в k3s

Перед применением манифестов должны существовать локальные секреты, которые не коммитятся:

- `infra/k3s/base/api-secret.yaml`
- `infra/k3s/base/postgres-secret.yaml`
- `infra/k3s/base/keycloak-secret.yaml`
- TLS/CA-файлы из `infra/tls/`

Проверка и применение base-манифестов:

```bash
kubectl apply --dry-run=server -k infra/k3s/base
kubectl apply -k infra/k3s/base
```

Проверка состояния:

```bash
kubectl -n task-manager-api get pods,svc,ingress,sts
kubectl -n cicd get pods
kubectl -n monitoring get pods
```

## CI/CD

`Jenkinsfile` описывает pipeline со стадиями:

```text
Checkout -> API Unit Tests -> Gitleaks -> Semgrep -> Trivy FS -> Build
-> Image Scan -> Push -> Deploy -> Rollout Check -> Smoke + RBAC Test
```

Ключевые параметры:

- `BUILD_AND_DEPLOY` - собрать, опубликовать и задеплоить образы.
- `RUN_SMOKE_TEST` - запустить bootstrap/smoke/RBAC проверки после деплоя.
- `SEMGREP_STRICT` - завершать pipeline при findings Semgrep.
- `TRIVY_STRICT` - завершать pipeline при HIGH/CRITICAL findings Trivy.
- `REGISTRY` - registry prefix, например `ghcr.io/kytaalok`.
- `REGISTRY_CREDS` - Jenkins credential ID для push/pull образов.

## Smoke и RBAC-проверки

Основной end-to-end скрипт:

```bash
SERVER_IP=83.69.249.206 \
NAMESPACE=task-manager-api \
JENKINS_NAMESPACE=cicd \
KEYCLOAK_ADMIN_PASSWORD=<password> \
bash infra/scripts/bootstrap_keycloak_and_smoke_test.sh
```

Скрипт генерации тестовой популяции Keycloak:

```bash
USER_COUNT=100 ADMIN_COUNT=10 DEVELOPER_COUNT=45 bash infra/scripts/create_keycloak_test_users.sh
```

Скрипт проверяет:

- готовность workloads в Kubernetes;
- доступность frontend, API, Keycloak, Jenkins и PostgreSQL;
- выдачу JWT через Keycloak;
- прикладной RBAC для `admin`, `developer`, `viewer`;
- Kubernetes RBAC через `kubectl auth can-i`;
- базовые smoke-сценарии CI/CD-инфраструктуры.

## Документация и артефакты

- `docs/testing/test-plan.md` - методика комплексного тестирования.
- `docs/testing/test-protocol.md` - протокол проверок.
- `docs/testing/artifacts/api-pytest.xml` - JUnit-отчёт pytest.
- `docs/appendices/` - материалы для раздела «Приложения» ВКР.

Перед публикацией отчётов и скриншотов нужно обезличить:

- публичные IP и домены, если требуется;
- JWT/PAT/token значения;
- пароли, cookies, private keys и реальные Kubernetes secrets.

## Правила хранения секретов

В git хранятся только шаблоны `*.example.*`.

Не коммитить:

- реальные Kubernetes Secret manifests;
- `.env` и `.env.*`;
- TLS private keys;
- PAT/JWT/token значения;
- локальные базы тестов и Python cache.

Актуальные правила описаны в `.gitignore`.
