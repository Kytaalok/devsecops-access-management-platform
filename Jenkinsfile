pipeline {
  agent {
    kubernetes {
      defaultContainer 'jnlp'
      yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: gitleaks
      image: ghcr.io/gitleaks/gitleaks:v8.30.0
      command:
        - sleep
      args:
        - "99d"
      tty: true
    - name: semgrep
      image: returntocorp/semgrep:1.160.0
      command:
        - sleep
      args:
        - "99d"
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
    booleanParam(name: 'RUN_SMOKE_TEST', defaultValue: false, description: 'Запустить infra/scripts/bootstrap_keycloak_and_smoke_test.sh')
    booleanParam(name: 'SEMGREP_STRICT', defaultValue: false, description: 'Падать, если Semgrep нашел проблемы')
    string(name: 'SERVER_IP', defaultValue: '83.69.249.206', description: 'Публичный IP VPS/стенда')
    string(name: 'NAMESPACE', defaultValue: 'task-manager-api', description: 'Namespace приложения')
    string(name: 'JENKINS_NAMESPACE', defaultValue: 'cicd', description: 'Namespace Jenkins')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

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
        always {
          archiveArtifacts artifacts: 'reports/gitleaks.sarif', allowEmptyArchive: true
        }
      }
    }

    stage('Semgrep') {
      steps {
        container('semgrep') {
          sh '''
            set -euo pipefail
            mkdir -p reports

            if [ "${SEMGREP_STRICT}" = "true" ]; then
              semgrep scan --config auto --metrics=off --json --output reports/semgrep.json .
            else
              semgrep scan --config auto --metrics=off --json --output reports/semgrep.json . || true
            fi
          '''
        }
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
