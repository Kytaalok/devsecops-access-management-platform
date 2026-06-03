# Infra (k3s)

Инфраструктурные манифесты для развёртывания Task Manager в `k3s`.

## Что должно быть в `infra/k3s/base`

- `namespace.yaml`
- `postgres-statefulset.yaml`
- `postgres-service.yaml` (headless + ClusterIP)
- `postgres-secret.yaml` (локально, не коммитить)
- `api-configmap.yaml`
- `api-deployment.yaml`
- `api-service.yaml`
- `api-secret.yaml` (локально, не коммитить)
- `keycloak-deployment.yaml`
- `keycloak-service.yaml`
- `frontend-deployment.yaml`
- `frontend-service.yaml`
- `ingress.yaml`
- `kustomization.yaml`

## Важно про секреты

- Реальные файлы `api-secret.yaml` и `postgres-secret.yaml` не должны попадать в git.
- В репозитории хранить только `*.example.yaml`.

## Деплой

```bash
kubectl apply --dry-run=server -k infra/k3s/base
kubectl apply -k infra/k3s/base
```

Если `kustomization.yaml` не используется:

```bash
kubectl apply -f infra/k3s/base/namespace.yaml
kubectl apply -f infra/k3s/base/
```

## Проверка состояния

```bash
kubectl -n task-manager-api get pods,svc,ingress,sts
kubectl -n task-manager-api get endpoints
kubectl -n task-manager-api get events --sort-by=.lastTimestamp | tail -n 30
```

## Внешние адреса (Ingress)

- `http://app.83.69.249.206.nip.io`
- `http://api.83.69.249.206.nip.io/health`
- `http://keycloak.83.69.249.206.nip.io`

## Образы без registry (локальный импорт в k3s)

Если используется `imagePullPolicy: Never`, импортируйте образ на обе ноды:

```bash
sudo k3s ctr images import <image>.tar
```

Проверка:

```bash
sudo k3s ctr images list | grep -E "task-manager-api|task-manager-frontend"
```

## Быстрый smoke-test API

```bash
curl -s http://api.83.69.249.206.nip.io/health
```

## Автоскрипт bootstrap + тесты

Скрипт создаёт/обновляет в Keycloak:
- realm,
- client,
- роли `admin/developer/viewer`,
- пользователей `admin1/dev1/viewer1`,
- а затем запускает smoke/RBAC проверки для `frontend/api/keycloak/postgres`.

Файл:
- `infra/scripts/bootstrap_keycloak_and_smoke_test.sh`

Запуск:

```bash
chmod +x infra/scripts/bootstrap_keycloak_and_smoke_test.sh
./infra/scripts/bootstrap_keycloak_and_smoke_test.sh
```

Переопределение параметров (пример):

```bash
SERVER_IP=83.69.249.206 \
KEYCLOAK_ADMIN_USER=admin \
KEYCLOAK_ADMIN_PASSWORD=admin \
USERS_PASSWORD=111 \
./infra/scripts/bootstrap_keycloak_and_smoke_test.sh
```

## Генерация тестовых пользователей Keycloak

Для проверки требования масштабирования до 100 пользователей используется отдельный идемпотентный скрипт:

```bash
USER_COUNT=100 \
ADMIN_COUNT=10 \
DEVELOPER_COUNT=45 \
USERS_PASSWORD=111 \
bash infra/scripts/create_keycloak_test_users.sh
```

По умолчанию создаются пользователи `loaduser001` ... `loaduser100`:

- `loaduser001` ... `loaduser010` — роль `admin`;
- `loaduser011` ... `loaduser055` — роль `developer`;
- `loaduser056` ... `loaduser100` — роль `viewer`.

Скрипт можно запускать повторно: существующие пользователи обновляются, пароль переустанавливается, роль назначается заново.
