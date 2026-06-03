# Приложение А. Манифесты Kubernetes (Kustomize base)

В приложении приведены основные Kubernetes-манифесты, используемые для развертывания тестового приложения, Keycloak, PostgreSQL, frontend, Ingress и RBAC-ресурсов. Секреты приведены только в виде example-файлов без реальных значений.

### Файл `infra/k3s/base/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: task-manager-api

````

### Файл `infra/k3s/base/api-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: task-manager-api
data:
  APP_ENV: "dev"
  AUTH_ENABLED: "true"
  JWT_ALGORITHM: "RS256"
  KEYCLOAK_ISSUER: "https://keycloak.83.69.249.206.nip.io/realms/devsecops"
  KEYCLOAK_CLIENT_ID: "task-manager-api"
  KEYCLOAK_AUDIENCE: "task-manager-api"
  KEYCLOAK_JWKS_URL: "http://keycloak-svc.task-manager-api.svc.cluster.local:8080/realms/devsecops/protocol/openid-connect/certs"
  CORS_ALLOW_ORIGINS: "http://app.83.69.249.206.nip.io"

````

### Файл `infra/k3s/base/api-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deploy
  namespace: task-manager-api
  labels:
    app: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      imagePullSecrets:
        - name: ghcr-pull-secret
      containers:
        - name: api
          image: ghcr.io/kytaalok/task-manager-api:latest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8000
              protocol: TCP
          envFrom:
            - configMapRef:
                name: api-config
            - secretRef:
                name: api-secret
````

### Файл `infra/k3s/base/api-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-svc
  namespace: task-manager-api
  labels:
    service: api
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
    - name: http
      port: 80
      targetPort: 8000
      protocol: TCP
````

### Файл `infra/k3s/base/api-secret.example.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-secret
  namespace: task-manager-api
type: Opaque
stringData:
  DATABASE_URL: "postgresql+psycopg2://db_user:db_password@postgres-svc:5432/db_name"

````

### Файл `infra/k3s/base/frontend-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deploy
  namespace: task-manager-api
  labels:
    app: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      imagePullSecrets:
        - name: ghcr-pull-secret
      containers:
        - name: frontend
          image: ghcr.io/kytaalok/task-manager-frontend:latest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 20
````

### Файл `infra/k3s/base/frontend-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: task-manager-api
  labels:
    app: frontend
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
````

### Файл `infra/k3s/base/postgres-statefulset.yaml`

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: task-manager-api
  labels:
    app: postgres
spec:
  serviceName: postgres-db-headless
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres-db
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: postgres
              containerPort: 5432
              protocol: TCP
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_USER
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_DB
          volumeMounts:
            - name: postgres-db-disk
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: postgres-db-disk
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 25Gi

````

### Файл `infra/k3s/base/postgres-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-db-headless
  namespace: task-manager-api
  labels:
    app: postgres
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-svc
  namespace: task-manager-api
  labels:
    app: postgres
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
      protocol: TCP

````

### Файл `infra/k3s/base/postgres-secret.example.yaml`

```yaml
````

### Файл `infra/k3s/base/keycloak-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: task-manager-api
  labels:
    app: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:26.1
          imagePullPolicy: IfNotPresent
          args: ["start-dev"]
          env:
            - name: KEYCLOAK_ADMIN
              valueFrom:
                secretKeyRef:
                  name: keycloak-secret
                  key: KEYCLOAK_ADMIN
            - name: KEYCLOAK_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-secret
                  key: KEYCLOAK_ADMIN_PASSWORD
            # База данных — тип и URL (не секреты)
            - name: KC_DB
              value: "postgres"
            - name: KC_DB_URL
              value: "jdbc:postgresql://postgres-svc:5432/keycloak"
            # Учётные данные БД — из Secret
            - name: KC_DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: keycloak-secret
                  key: KC_DB_USERNAME
            - name: KC_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-secret
                  key: KC_DB_PASSWORD
            # Прокси и hostname (TLS-терминация на Traefik)
            - name: KC_PROXY_HEADERS
              value: "xforwarded"
            - name: KC_HOSTNAME
              value: "keycloak.83.69.249.206.nip.io"
            - name: KC_HTTP_ENABLED
              value: "true"
            - name: KC_HOSTNAME_STRICT
              value: "false"
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP

````

### Файл `infra/k3s/base/keycloak-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: keycloak-svc
  namespace: task-manager-api
  labels:
    service: keycloak
spec:
  type: ClusterIP
  selector:
    app: keycloak
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
````

### Файл `infra/k3s/base/keycloak-secret.example.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-secret
  namespace: task-manager-api
type: Opaque
stringData:
  KEYCLOAK_ADMIN: "admin"
  KEYCLOAK_ADMIN_PASSWORD: "changeme"
  KC_DB_USERNAME: "task_user"
  KC_DB_PASSWORD: "changeme"

````

### Файл `infra/k3s/base/keycloak-ingress-tls.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak-tls
  namespace: task-manager-api
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - keycloak.83.69.249.206.nip.io
      secretName: keycloak-tls-secret
  rules:
    - host: keycloak.83.69.249.206.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keycloak-svc
                port:
                  number: 8080

````

### Файл `infra/k3s/base/keycloak-tls-secret.example.yaml`

```yaml
#   kubectl create secret tls keycloak-tls-secret \
#     -n task-manager-api \
#     --cert=infra/tls/keycloak.crt \
#     --key=infra/tls/keycloak.key
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-tls-secret
  namespace: task-manager-api
type: kubernetes.io/tls
data:
  tls.crt: "<base64-encoded-certificate>"
  tls.key: "<base64-encoded-private-key>"

````

### Файл `infra/k3s/base/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: task-manager-api
spec:
  ingressClassName: traefik
  rules:
    - host: app.83.69.249.206.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-svc
                port:
                  number: 80
    - host: api.83.69.249.206.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 80
    - host: keycloak.83.69.249.206.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: keycloak-svc
                port:
                  number: 8080

````

### Файл `infra/k3s/base/rbac-clusterroles.yaml`

```yaml
# Кастомные ClusterRole для ролей из Keycloak.
# Группы приходят в JWT с префиксом oidc: (настроено в k3s OIDC).
#
# Соответствие:
#   Keycloak role "admin"     -> OIDC group "oidc:admin"     -> ClusterRole diploma:admin
#   Keycloak role "developer" -> OIDC group "oidc:developer" -> ClusterRole diploma:developer
#   Keycloak role "viewer"    -> OIDC group "oidc:viewer"    -> ClusterRole diploma:viewer

---
# diploma:admin — видит кластерные ресурсы (nodes, ns, PV).
# Полный доступ к namespace-ресурсам выдаётся через RoleBinding (см. rbac-bindings.yaml).
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: diploma:admin
  labels:
    app.kubernetes.io/part-of: diploma-rbac
rules:
  - apiGroups: [""]
    resources: ["nodes", "namespaces", "persistentvolumes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes"]
    verbs: ["get", "list"]

---
# diploma:developer — деплой и мониторинг приложений.
# Применяется через RoleBinding в конкретном namespace.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: diploma:developer
  labels:
    app.kubernetes.io/part-of: diploma-rbac
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/status
      - services
      - endpoints
      - configmaps
      - events
      - persistentvolumeclaims
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]

---
# diploma:viewer — только чтение, без секретов и без записи.
# Применяется через RoleBinding в конкретном namespace.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: diploma:viewer
  labels:
    app.kubernetes.io/part-of: diploma-rbac
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/status
      - services
      - endpoints
      - configmaps
      - events
      - persistentvolumeclaims
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch"]

````

### Файл `infra/k3s/base/rbac-bindings.yaml`

```yaml
# Привязки OIDC-групп из Keycloak к ClusterRole/Role в Kubernetes.
#
# OIDC-группы формируются k3s из JWT-claim "groups" с префиксом "oidc:".
# Пример: роль Keycloak "developer" -> группа k8s "oidc:developer".

# ──────────────────────────────────────────────────────────────
# ADMIN
# ──────────────────────────────────────────────────────────────

---
# Кластерный уровень: admin видит nodes, namespaces, PV
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: diploma:admin-cluster
  labels:
    app.kubernetes.io/part-of: diploma-rbac
subjects:
  - kind: Group
    name: "oidc:admin"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: diploma:admin
  apiGroup: rbac.authorization.k8s.io

---
# Namespace task-manager-api: admin получает полный контроль (встроенная роль admin)
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: diploma:admin
  namespace: task-manager-api
  labels:
    app.kubernetes.io/part-of: diploma-rbac
subjects:
  - kind: Group
    name: "oidc:admin"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io

---
# Namespace cicd (Jenkins): admin получает полный контроль
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: diploma:admin
  namespace: cicd
  labels:
    app.kubernetes.io/part-of: diploma-rbac
subjects:
  - kind: Group
    name: "oidc:admin"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io

# ──────────────────────────────────────────────────────────────
# DEVELOPER
# ──────────────────────────────────────────────────────────────

---
# Namespace task-manager-api: developer деплоит и мониторит, не трогает секреты
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: diploma:developer
  namespace: task-manager-api
  labels:
    app.kubernetes.io/part-of: diploma-rbac
subjects:
  - kind: Group
    name: "oidc:developer"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: diploma:developer
  apiGroup: rbac.authorization.k8s.io

# ──────────────────────────────────────────────────────────────
# VIEWER
# ──────────────────────────────────────────────────────────────

---
# Namespace task-manager-api: viewer только читает, без секретов и без записи
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: diploma:viewer
  namespace: task-manager-api
  labels:
    app.kubernetes.io/part-of: diploma-rbac
subjects:
  - kind: Group
    name: "oidc:viewer"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: diploma:viewer
  apiGroup: rbac.authorization.k8s.io

# ──────────────────────────────────────────────────────────────
# JENKINS SMOKE TEST
# Позволяет Jenkins SA (ns cicd) выполнять smoke-тесты в task-manager-api:
# rollout status, get endpoints/secrets, exec в postgres pod.
# ──────────────────────────────────────────────────────────────

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: diploma:jenkins-smoke
  namespace: task-manager-api
  labels:
    app.kubernetes.io/part-of: diploma-rbac
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "endpoints", "secrets", "services"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "replicasets"]
    verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: diploma:jenkins-smoke
  namespace: task-manager-api
  labels:
    app.kubernetes.io/part-of: diploma-rbac
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: cicd
roleRef:
  kind: Role
  name: diploma:jenkins-smoke
  apiGroup: rbac.authorization.k8s.io

````

### Файл `infra/k3s/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: task-manager-api
resources:
  - namespace.yaml
  - api-configmap.yaml
  - api-service.yaml
  - api-deployment.yaml
  - api-secret.yaml
  - postgres-secret.yaml
  - postgres-service.yaml
  - postgres-statefulset.yaml
  - keycloak-secret.yaml
  - keycloak-service.yaml
  - keycloak-deployment.yaml
  - keycloak-ingress-tls.yaml
  - frontend-service.yaml
  - frontend-deployment.yaml
  - ingress.yaml
  - rbac-clusterroles.yaml
  - rbac-bindings.yaml

````

