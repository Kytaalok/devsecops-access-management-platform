pipeline {
  agent any
  
  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    skipDefaultCheckout(true)
  }

  parameters {
    booleanParam(name: 'RUN_SMOKE_TEST', defaultValue: false, description: 'Запустить infra/scripts/bootstrap_keycloak_and_smoke_test.sh')
    booleanParam(name: 'SEMGREP_STRICT', defaultValue: false, description: 'Падать, если Semgrep нашел проблемы')
    string(name: 'SERVER_IP', defaultValue: '83.69.249.206', description: 'Публичный IP VPS/стенда')
    string(name: 'NAMESPACE', defaultValue: 'task-manager-api', description: 'Namespace приложения')
    string(name: 'JENKINS_NAMESPACE', defaultValue: 'cicd', description: 'Namespace Jenkins')
  }

  environment {
    GITLEAKS_VERSION = '8.30.0'
    SEMGREP_VERSION  = '1.91.0'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Gitleaks') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p reports

          run_scan() {
            "$1" git . \
              --redact \
              --report-format sarif \
              --report-path reports/gitleaks.sarif \
              --exit-code 1
          }

          if command -v gitleaks >/dev/null 2>&1; then
            echo "[INFO] Using installed gitleaks binary"
            run_scan "$(command -v gitleaks)"
            exit 0
          fi

          if command -v docker >/dev/null 2>&1; then
            echo "[INFO] Using gitleaks docker image"
            docker run --rm -v "$PWD:/repo" -w /repo ghcr.io/gitleaks/gitleaks:v${GITLEAKS_VERSION} \
              gitleaks git . \
                --redact \
                --report-format sarif \
                --report-path reports/gitleaks.sarif \
                --exit-code 1
            exit 0
          fi

          echo "[INFO] Downloading gitleaks binary"
          ARCH="$(uname -m)"
          case "$ARCH" in
            x86_64|amd64) ASSET_ARCH="x64" ;;
            aarch64|arm64) ASSET_ARCH="arm64" ;;
            *) echo "[ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
          esac

          curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${ASSET_ARCH}.tar.gz" \
            | tar -xz -C . gitleaks
          chmod +x ./gitleaks
          run_scan "./gitleaks"
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/gitleaks.sarif', allowEmptyArchive: true
        }
      }
    }

    stage('Semgrep') {
      steps {
        sh '''
          set -euo pipefail
          mkdir -p reports

          run_semgrep_local() {
            if [ "${SEMGREP_STRICT}" = "true" ]; then
              semgrep scan --config auto --metrics=off --json --output reports/semgrep.json .
            else
              semgrep scan --config auto --metrics=off --json --output reports/semgrep.json . || true
            fi
          }

          run_semgrep_docker() {
            if [ "${SEMGREP_STRICT}" = "true" ]; then
              docker run --rm -v "$PWD:/src" -w /src --entrypoint semgrep semgrep/semgrep:${SEMGREP_VERSION} \
                scan --config auto --metrics=off --json --output reports/semgrep.json .
            else
              docker run --rm -v "$PWD:/src" -w /src --entrypoint semgrep semgrep/semgrep:${SEMGREP_VERSION} \
                scan --config auto --metrics=off --json --output reports/semgrep.json . || true
            fi
          }

          if command -v semgrep >/dev/null 2>&1; then
            echo "[INFO] Using installed semgrep"
            run_semgrep_local
            exit 0
          fi

          if command -v docker >/dev/null 2>&1; then
            echo "[INFO] Using semgrep docker image"
            run_semgrep_docker
            exit 0
          fi

          echo "[ERROR] Neither semgrep nor docker found on agent"
          exit 1
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/semgrep.json', allowEmptyArchive: true
        }
      }
    }

    stage('Smoke Test') {
      when {
        expression { return params.RUN_SMOKE_TEST }
      }
      steps {
        sh '''
          set -euo pipefail
          export SERVER_IP="${SERVER_IP}"
          export NAMESPACE="${NAMESPACE}"
          export JENKINS_NAMESPACE="${JENKINS_NAMESPACE}"
          bash infra/scripts/bootstrap_keycloak_and_smoke_test.sh
        '''
      }
    }
  }
}
