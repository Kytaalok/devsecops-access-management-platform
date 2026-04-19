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


