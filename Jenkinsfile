pipeline {
  agent {
    kubernetes {
      defaultContainer 'jnlp'
      yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  volumes:
    - name: docker-sock
      hostPath:
        path: /var/run/docker.sock
  containers:
    - name: gitleaks
      image: ghcr.io/gitleaks/gitleaks:v8.30.0
      command: ["sleep"]
      args: ["99d"]
      tty: true
    - name: semgrep
      image: returntocorp/semgrep:1.160.0
      command: ["sleep"]
      args: ["99d"]
      tty: true
    - name: trivy
      image: aquasec/trivy:latest
      command: ["sleep"]
      args: ["99d"]
      tty: true
      volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
    - name: docker
      image: docker:27-cli
      command: ["sleep"]
      args: ["99d"]
      tty: true
      volumeMounts:
        - name: docker-sock
          mountPath: /var/run/docker.sock
    - name: python
      image: python:3.12-slim
      command: ["sleep"]
      args: ["99d"]
      tty: true
    - name: kubectl
      image: alpine/k8s:1.30.4
      command: ["sleep"]
      args: ["99d"]
      tty: true
'''
    }
  }

  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    skipDefaultCheckout(true)
  }

  parameters {
    booleanParam(name: 'BUILD_AND_DEPLOY', defaultValue: true,
      description: 'Собрать образы, задеплоить и проверить rollout')
    string(name: 'REGISTRY', defaultValue: 'ghcr.io/kytaalok',
      description: 'Prefix реестра образов (ghcr.io/username или docker.io/username)')
    string(name: 'REGISTRY_CREDS', defaultValue: 'ghcr-token',
      description: 'ID Jenkins-credential (Username+Password) для push/pull образов')
    booleanParam(name: 'RUN_SMOKE_TEST', defaultValue: false,
      description: 'Запустить bootstrap + smoke + RBAC тесты после деплоя')
    booleanParam(name: 'SEMGREP_STRICT', defaultValue: false,
      description: 'Завершать pipeline с ошибкой, если Semgrep нашёл проблемы')
    booleanParam(name: 'TRIVY_STRICT', defaultValue: false,
      description: 'Завершать pipeline с ошибкой, если Trivy нашёл HIGH/CRITICAL')
    string(name: 'TRIVY_SEVERITY', defaultValue: 'HIGH,CRITICAL',
      description: 'Уровни уязвимостей для Trivy (FS и Image scan)')
    string(name: 'SERVER_IP', defaultValue: '83.69.249.206',
      description: 'Публичный IP VPS/стенда')
    string(name: 'NAMESPACE', defaultValue: 'task-manager-api',
      description: 'Namespace приложения')
    string(name: 'JENKINS_NAMESPACE', defaultValue: 'cicd',
      description: 'Namespace Jenkins')
  }

  environment {
    SEMGREP_CONFIG = 'p/ci'
  
    REGISTRY = "${params.REGISTRY}"
    TRIVY_SEVERITY = "${params.TRIVY_SEVERITY}"
    SERVER_IP = "${params.SERVER_IP}"
    NAMESPACE = "${params.NAMESPACE}"
    JENKINS_NAMESPACE = "${params.JENKINS_NAMESPACE}"
  
    SEMGREP_STRICT = "${params.SEMGREP_STRICT}"
    TRIVY_STRICT = "${params.TRIVY_STRICT}"
  }
  
  stages {

    // ─────────────────────────────────────────────────────────────────────────
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.IMAGE_TAG = sh(
            returnStdout: true,
            script: 'git rev-parse --short HEAD'
          ).trim()
    
          echo "IMAGE_TAG=${env.IMAGE_TAG}  REGISTRY=${env.REGISTRY}"
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('API Unit Tests') {
      steps {
        container('python') {
          sh '''
            set -euo pipefail
            cd services/task-manager-api
            python -m pip install --no-cache-dir -r requirements.txt
            mkdir -p ../../reports
            PYTHONPATH="$PWD" python -m pytest -q --junitxml=../../reports/api-pytest.xml
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/api-pytest.xml', allowEmptyArchive: true
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Gitleaks') {
      steps {
        container('gitleaks') {
          sh '''
            set -euo pipefail
            mkdir -p reports
            gitleaks git . \
              --redact \
              --report-format sarif \
              --report-path reports/gitleaks.sarif \
              --exit-code 1
          '''
        }
      }
      post {
        always { archiveArtifacts artifacts: 'reports/gitleaks.sarif', allowEmptyArchive: true }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Semgrep') {
      steps {
        container('semgrep') {
          sh '''
            set -euo pipefail
            mkdir -p reports
            if [ "${SEMGREP_STRICT}" = "true" ]; then
              semgrep scan --config "${SEMGREP_CONFIG}" --metrics=off --json --output reports/semgrep.json .
            else
              semgrep scan --config "${SEMGREP_CONFIG}" --metrics=off --json --output reports/semgrep.json . || true
            fi
          '''
        }
      }
      post {
        always { archiveArtifacts artifacts: 'reports/semgrep.json', allowEmptyArchive: true }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Trivy FS') {
      steps {
        container('trivy') {
          sh '''
            set -euo pipefail
            mkdir -p reports .trivycache
            trivy fs . \
              --cache-dir .trivycache \
              --no-progress \
              --format sarif \
              --output reports/trivy-fs.sarif \
              --severity "${TRIVY_SEVERITY}" \
              --scanners vuln,secret \
              --exit-code 0
            if [ "${TRIVY_STRICT}" = "true" ]; then
              trivy fs . \
                --cache-dir .trivycache \
                --no-progress \
                --format table \
                --severity "${TRIVY_SEVERITY}" \
                --scanners vuln,secret \
                --exit-code 1
            fi
          '''
        }
      }
      post {
        always { archiveArtifacts artifacts: 'reports/trivy-fs.sarif', allowEmptyArchive: true }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Build') {
      when { expression { return params.BUILD_AND_DEPLOY } }
      steps {
        container('docker') {
          sh '''
            set -euo pipefail
            REGISTRY="${REGISTRY}"
            TAG="${IMAGE_TAG}"

            echo ">>> Building API image: ${REGISTRY}/task-manager-api:${TAG}"
            docker build \
              -t "${REGISTRY}/task-manager-api:${TAG}" \
              -t "${REGISTRY}/task-manager-api:latest" \
              ./services/task-manager-api/

            echo ">>> Building Frontend image: ${REGISTRY}/task-manager-frontend:${TAG}"
            docker build \
              -t "${REGISTRY}/task-manager-frontend:${TAG}" \
              -t "${REGISTRY}/task-manager-frontend:latest" \
              ./services/task-manager-frontend/

            echo ">>> Built images:"
            docker images | grep task-manager
          '''
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Image Scan') {
      when { expression { return params.BUILD_AND_DEPLOY } }
      steps {
        container('trivy') {
          sh '''
            set -euo pipefail
            mkdir -p reports .trivycache
            REGISTRY="${REGISTRY}"
            TAG="${IMAGE_TAG}"

            echo ">>> Scanning API image..."
            trivy image \
              --cache-dir .trivycache \
              --no-progress \
              --format sarif \
              --output reports/trivy-image-api.sarif \
              --severity "${TRIVY_SEVERITY}" \
              --exit-code 0 \
              "${REGISTRY}/task-manager-api:${TAG}"

            echo ">>> Scanning Frontend image..."
            trivy image \
              --cache-dir .trivycache \
              --no-progress \
              --format sarif \
              --output reports/trivy-image-frontend.sarif \
              --severity "${TRIVY_SEVERITY}" \
              --exit-code 0 \
              "${REGISTRY}/task-manager-frontend:${TAG}"

            if [ "${TRIVY_STRICT}" = "true" ]; then
              trivy image --cache-dir .trivycache --no-progress --format table \
                --severity "${TRIVY_SEVERITY}" --exit-code 1 \
                "${REGISTRY}/task-manager-api:${TAG}"
              trivy image --cache-dir .trivycache --no-progress --format table \
                --severity "${TRIVY_SEVERITY}" --exit-code 1 \
                "${REGISTRY}/task-manager-frontend:${TAG}"
            fi
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/trivy-image-*.sarif', allowEmptyArchive: true
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Push') {
      when { expression { return params.BUILD_AND_DEPLOY } }
      steps {
        container('docker') {
          withCredentials([usernamePassword(
            credentialsId: params.REGISTRY_CREDS,
            usernameVariable: 'REG_USER',
            passwordVariable: 'REG_PASS'
          )]) {
            sh '''
              set -euo pipefail
              REGISTRY="${REGISTRY}"
              TAG="${IMAGE_TAG}"
              REGISTRY_HOST="$(echo "${REGISTRY}" | cut -d/ -f1)"

              echo "${REG_PASS}" | docker login "${REGISTRY_HOST}" -u "${REG_USER}" --password-stdin

              docker push "${REGISTRY}/task-manager-api:${TAG}"
              docker push "${REGISTRY}/task-manager-api:latest"
              docker push "${REGISTRY}/task-manager-frontend:${TAG}"
              docker push "${REGISTRY}/task-manager-frontend:latest"

              docker logout "${REGISTRY_HOST}" || true
              echo ">>> Pushed ${REGISTRY}/task-manager-api:${TAG}"
              echo ">>> Pushed ${REGISTRY}/task-manager-frontend:${TAG}"
            '''
          }
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Deploy') {
      when { expression { return params.BUILD_AND_DEPLOY } }
      steps {
        container('kubectl') {
          withCredentials([usernamePassword(
            credentialsId: params.REGISTRY_CREDS,
            usernameVariable: 'REG_USER',
            passwordVariable: 'REG_PASS'
          )]) {
            sh '''
              set -euo pipefail
    
              REGISTRY="${REGISTRY}"
              TAG="${IMAGE_TAG}"
              NS="${NAMESPACE}"
              REGISTRY_HOST="$(echo "${REGISTRY}" | cut -d/ -f1)"
    
              echo ">>> Creating/updating ghcr-pull-secret in namespace ${NS}..."
              kubectl create secret docker-registry ghcr-pull-secret \
                --docker-server="${REGISTRY_HOST}" \
                --docker-username="${REG_USER}" \
                --docker-password="${REG_PASS}" \
                -n "${NS}" \
                --dry-run=client -o yaml | kubectl apply -f -
    
              echo ">>> Patching api-deploy imagePullSecrets and imagePullPolicy..."
              kubectl patch deployment api-deploy \
                -n "${NS}" \
                --type strategic \
                -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}],"containers":[{"name":"api","imagePullPolicy":"Always"}]}}}}'
    
              echo ">>> Patching frontend-deploy imagePullSecrets and imagePullPolicy..."
              kubectl patch deployment frontend-deploy \
                -n "${NS}" \
                --type strategic \
                -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}],"containers":[{"name":"frontend","imagePullPolicy":"Always"}]}}}}'
    
              echo ">>> Updating images to tag ${TAG}..."
              kubectl set image deployment/api-deploy \
                api="${REGISTRY}/task-manager-api:${TAG}" \
                -n "${NS}"
    
              kubectl set image deployment/frontend-deploy \
                frontend="${REGISTRY}/task-manager-frontend:${TAG}" \
                -n "${NS}"
    
              echo ">>> Annotating deployments with build metadata..."
              kubectl annotate deployment api-deploy frontend-deploy \
                -n "${NS}" \
                --overwrite \
                deploy.kubernetes.io/image-tag="${TAG}" \
                deploy.kubernetes.io/deployed-by="jenkins-build-${BUILD_NUMBER}"
            '''
          }
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Rollout Check') {
      when { expression { return params.BUILD_AND_DEPLOY } }
      steps {
        container('kubectl') {
          sh '''
            set -euo pipefail
            NS="${NAMESPACE}"

            echo ">>> Waiting for api-deploy rollout..."
            kubectl rollout status deployment/api-deploy -n "${NS}" --timeout=180s

            echo ">>> Waiting for frontend-deploy rollout..."
            kubectl rollout status deployment/frontend-deploy -n "${NS}" --timeout=180s

            echo ">>> Final pod status:"
            kubectl get pods -n "${NS}" -l "app in (api,frontend)" \
              -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready"
          '''
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    stage('Smoke + RBAC Test') {
      when { expression { return params.RUN_SMOKE_TEST } }
      steps {
        container('kubectl') {
          withCredentials([string(
            credentialsId: 'keycloak-admin-password',
            variable: 'KEYCLOAK_ADMIN_PASSWORD'
          )]) {
            sh '''
              set -euo pipefail
    
              mkdir -p reports
    
              export SERVER_IP="${SERVER_IP}"
              export NAMESPACE="${NAMESPACE}"
              export JENKINS_NAMESPACE="${JENKINS_NAMESPACE}"
              export KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"
    
              if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
                cat /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/diploma-ca.crt > /tmp/combined-ca.crt
              else
                cp /etc/ssl/certs/diploma-ca.crt /tmp/combined-ca.crt
              fi
    
              export CURL_CA_BUNDLE="/tmp/combined-ca.crt"
              export SSL_CERT_FILE="/tmp/combined-ca.crt"
    
              bash infra/scripts/bootstrap_keycloak_and_smoke_test.sh 2>&1 | tee reports/smoke-test.log
            '''
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/smoke-test.log', allowEmptyArchive: true
        }
      }
    }

  }

  post {
    success {
      echo "Pipeline SUCCESS — IMAGE_TAG=${env.IMAGE_TAG ?: 'n/a'}"
    }
    failure {
      echo "Pipeline FAILED — IMAGE_TAG=${env.IMAGE_TAG ?: 'n/a'}"
    }
  }
}
