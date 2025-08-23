pipeline {
  // --- CHOOSE ONE AGENT STRATEGY ---
  // agent {  // <<=== Multi-container Kubernetes cloud agent
  //   kubernetes {
  //     cloud 'kubernetes'
  //     namespace 'cicd'
  //     defaultContainer 'go'
  //     yaml """ ... """   // podTemplate YAML
  //   }
  // }

  // agent any  // <<=== Single container agent (default Jenkins agent)

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
  # Pull once per node then reuse
  imagePullSecrets:
    - name: jenkins-secrets
  containers:
    - name: go
      image: golang:1.25-alpine
      imagePullPolicy: IfNotPresent
      command: ['sh', '-c', 'cat']
      tty: true
      securityContext:
        runAsUser: 0
      env:
        - name: CGO_ENABLED
          value: "0"
      volumeMounts:
        - name: trivy-cache
          mountPath: /root/.cache/trivy

    - name: sonar
      image: sonarsource/sonar-scanner-cli:latest
      imagePullPolicy: IfNotPresent
      command: ['sh', '-c', 'cat']
      tty: true

    - name: trivy
      image: aquasec/trivy:latest
      imagePullPolicy: IfNotPresent
      command: ['sh', '-c', 'cat']
      tty: true
      securityContext:
        runAsUser: 0
      volumeMounts:
        - name: trivy-cache
          mountPath: /root/.cache/trivy

    - name: buildkit
      image: moby/buildkit:latest
      imagePullPolicy: IfNotPresent
      securityContext:
        privileged: true
      command: ["buildkitd", "--rootless"]
      tty: true

    - name: helm
      image: dtzar/helm-kubectl:latest
      imagePullPolicy: IfNotPresent
      command: ['sh', '-c', 'cat']
      tty: true

  volumes:
    - name: trivy-cache
      emptyDir: {}
"""
    }
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '33')) // keep last 33 builds
    skipDefaultCheckout(true)
    timestamps() // add timestamps to console output
    ansiColor('xterm') // use ANSI colors in console output
  }

  environment {
    // --- Variables defined here inside the pipeline ---
    REGISTRY = 'docker.io/angel3' // Docker registry URL      
    IMAGE    = 'simple-go-service'
    TAG      = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : env.BUILD_NUMBER}"
    CHART    = 'helm/simple-go-service' // Helm chart path
    APP_NS   = 'sgsvc'                  // Kubernetes namespace for the app
  }

  stages {
    // --- Checkout source code ---
    stage('Checkout') {
      steps {
        checkout scm
        sh 'ls -la'
      }
    }

    stage('Deps') {
      // --- Install dependencies ---
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
      // --- Run tests and generate coverage reports ---
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
      // --- Run static code analysis ---
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
      // --- Scan the filesystem for vulnerabilities ---
      steps {
        container('trivy') {
          sh '''
            trivy fs --no-progress --severity HIGH,CRITICAL --exit-code 0 -f table .
          '''
        }
      }
    }

    stage('Build & Push (BuildKit)') {
      // --- Build the Docker image using BuildKit and push to registry ---
      steps {
        container('buildkit') {
          withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
            script {
              def TAG = env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : env.BUILD_NUMBER
              def REGISTRY = "docker.io"
              def IMAGE = "angel3/simple-go-service"

              sh """
                echo "🚀 Starting BuildKit build..."
                echo "🔖 Tagging image as ${REGISTRY}/${IMAGE}:${TAG}"

                buildctl build \
                  --frontend=dockerfile.v0 \
                  --local context=. \
                  --local dockerfile=. \
                  --output type=image,"name=${REGISTRY}/${IMAGE}:${TAG},push=true" \
                  --opt "oci-mediatypes=true" \
                  --opt "build-arg:BUILDKIT_INLINE_CRED_HELPER=${REGISTRY}" \
                  --secret id=registry,user=${DOCKERHUB_USER},pass=${DOCKERHUB_PASS}
              """
            }
          }
        }
      }
    }

    stage('Image Scan (Trivy)') {
      // --- Scan the Docker image for vulnerabilities ---
      when {
        expression { return env.REGISTRY && env.IMAGE && env.TAG }
      }
      steps {
        container('trivy') {
          sh '''
            trivy image --no-progress --severity HIGH,CRITICAL --exit-code 0 ${REGISTRY}/${IMAGE}:${TAG}
          '''
        }
      }
    }

    stage('SonarCloud') {
      // --- Run SonarCloud analysis ---
      when {
        expression { return env.REGISTRY && env.IMAGE && env.TAG }
      }
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
      // --- Deploy the application using Helm ---
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

    // =============================
    // Service Monitoring & Alerting
    // =============================
    stage('Service Monitoring') {
      steps {
        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
          // This stage will not fail the pipeline, but will mark it as UNSTABLE if the health check fails
          echo "Performing service health check..."
        }
        script {
          // Perform a health check on the service
          // --- Use ClusterIP service URL (inside cluster); NodePort only if external ---
          def serviceUrl = "http://simple-go-service.${APP_NS}.svc.cluster.local:8080/v1/data"
          echo "Performing service health check on ${serviceUrl}..."

          def response = sh(script: "curl -s -o /dev/null -w '%{http_code}' ${serviceUrl}", returnStdout: true).trim()
          echo "Health check HTTP response: ${response}"

          if (response != "200") {
            // Send email if the service is down
            emailext(
              subject: "🚨⚠️ ALERT: Service health check failed",
              body: "Service check to ${serviceUrl} returned ${response}",
              to: "mock-alert@example.com"  // TODO: replace with real email
            )
            error("Service health check failed!") // This will mark the stage as FAILED but not the entire pipeline
          }
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
