pipeline {
  agent {
    kubernetes {
      cloud 'kubernetes'
      namespace 'cicd'
      defaultContainer 'go'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jx-build
spec:
  serviceAccountName: jenkins
  containers:
    - name: go
      image: golang:1.25-alpine
      command: ['cat']
      tty: true
      env:
        - name: CGO_ENABLED
          value: "0"
      volumeMounts:
        - name: trivy-cache
          mountPath: /root/.cache/trivy
    - name: sonar
      image: sonarsource/sonar-scanner-cli:latest
      command: ['cat']
      tty: true
    - name: trivy
      image: aquasec/trivy:latest
      securityContext:
        runAsUser: 0
      command: ['cat']
      tty: true
      volumeMounts:
        - name: trivy-cache
          mountPath: /root/.cache/trivy
    - name: kaniko
      image: gcr.io/kaniko-project/executor:latest
      args: ["--version"]
      volumeMounts:
        - name: docker-config
          mountPath: /kaniko/.docker
          readOnly: true
    - name: helm
      image: dtzar/helm-kubectl:latest
      command: ['cat']
      tty: true
  volumes:
    - name: docker-config
      secret:
        secretName: regcred
        items:
          - key: .dockerconfigjson
            path: config.json
    - name: trivy-cache
      emptyDir: {}
"""
    }
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    skipDefaultCheckout(true)
  }

  environment {
    REGISTRY = 'docker.io/angel3'
    IMAGE    = 'simple-go-service'
    TAG      = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : env.BUILD_NUMBER}"
    CHART    = 'helm/simple-go-service'
    APP_NS   = 'sgsvc'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'ls -la'
      }
    }

    stage('Deps') {
      steps {
        container('go') {
          sh '''
            apk add --no-cache git bash curl make jq
            go version
            go mod tidy
          '''
        }
      }
    }

    stage('Test & Coverage (Ginkgo)') {
      steps {
        container('go') {
          sh '''
            go install github.com/onsi/ginkgo/v2/ginkgo@latest
            go install github.com/jstemmer/go-junit-report@latest || true
            mkdir -p reports
            if ls **/*_test.go >/dev/null 2>&1; then
              ginkgo -r -p -cover -output-dir=reports -junit-report reports/junit.xml \
                     -coverprofile=coverage-ginkgo.out || true
            fi
            go test ./... -coverprofile=coverage-unit.out -v 2>&1 | go-junit-report > reports/junit-go.xml || true
            echo "mode: set" > coverage.out
            if [ -f coverage-unit.out ]; then tail -n +2 coverage-unit.out >> coverage.out || true; fi
            if [ -f coverage-ginkgo.out ]; then tail -n +2 coverage-ginkgo.out >> coverage.out || true; fi
          '''
        }
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'reports/*.xml'
          archiveArtifacts allowEmptyArchive: true, artifacts: 'coverage*.out, reports/*'
        }
      }
    }

    stage('Static Analysis (gosec)') {
      steps {
        container('go') {
          sh '''
            go install github.com/securego/gosec/v2/cmd/gosec@latest
            gosec -fmt=junit-xml -out reports/gosec.xml ./... || true
          '''
        }
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'reports/gosec.xml'
        }
      }
    }

    stage('Filesystem Scan (Trivy)') {
      steps {
        container('trivy') {
          sh '''
            trivy fs --no-progress --severity HIGH,CRITICAL --exit-code 0 -f table .
          '''
        }
      }
    }

    stage('Build & Push (Kaniko)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          container('kaniko') {
            sh '''
              echo "{\"auths\":{\"https://index.docker.io/v1/\":{\"username\":\"$DOCKER_USER\",\"password\":\"$DOCKER_PASS\"}}}" > /kaniko/.docker/config.json
              executor \
                --context=$WORKSPACE \
                --dockerfile=$WORKSPACE/Dockerfile \
                --destination=${REGISTRY}/${IMAGE}:${TAG} \
                --cache=true --verbosity=info
            '''
          }
        }
      }
    }

    stage('Image Scan (Trivy)') {
      steps {
        container('trivy') {
          sh '''
            trivy image --no-progress --severity HIGH,CRITICAL --exit-code 0 ${REGISTRY}/${IMAGE}:${TAG}
          '''
        }
      }
    }

    stage('SonarCloud') {
      steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
          container('sonar') {
            sh '''
              sonar-scanner \
                -Dsonar.projectKey=meleksabit_simple-go-service \
                -Dsonar.organization=meleksabit \
                -Dsonar.host.url=https://sonarcloud.io \
                -Dsonar.login=$SONAR_TOKEN \
                -Dsonar.go.coverage.reportPaths=coverage.out
            '''
          }
        }
      }
    }

    stage('Deploy (Helm rolling update)') {
      when {
        expression { return !(changeRequest() && env.BRANCH_NAME != 'main') }
      }
      steps {
        container('helm') {
          sh '''
            helm version && kubectl version --client
            kubectl get ns ${APP_NS} || kubectl create ns ${APP_NS}
            helm upgrade --install simple-go-service ${CHART} \
              --namespace ${APP_NS} \
              --set image.repository=${REGISTRY}/${IMAGE} \
              --set image.tag=${TAG} \
              --wait --timeout 5m
            kubectl -n ${APP_NS} rollout status deploy/simple-go-service --timeout=120s
          '''
        }
      }
    }
  }

  post {
    success {
      echo "✅ Pipeline OK — image ${REGISTRY}/${IMAGE}:${TAG}"
    }
    failure {
      echo "❌ Pipeline failed"
    }
  }
}
