pipeline {
    agent any

    environment {
        REGISTRY = 'docker.io/angel3'
        IMAGE    = 'simple-go-service'
        TAG      = "dev-${GIT_COMMIT[0..6]}"
        SONAR_TOKEN = credentials('sonar-token')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Deps') {
            steps {
                sh 'go mod tidy'
            }
        }

        stage('Test') {
            steps {
                sh '''
                  # Run unit tests
                  go test ./... -coverprofile=coverage-unit.out -v

                  # Run Ginkgo tests if available
                  if command -v ginkgo >/dev/null 2>&1; then
                    ginkgo -r -p -cover -coverprofile=coverage-ginkgo.out \
                           -outputdir=. \
                           -json-report=ginkgo-report.json \
                           -junit-report=report.xml
                  fi

                  # Merge coverage files
                  echo "mode: set" > coverage.out
                  tail -n +2 coverage-unit.out >> coverage.out || true
                  tail -n +2 coverage-ginkgo.out >> coverage.out || true
                '''
            }
            post {
                always {
                    junit 'report.xml'
                }
            }
        }

        stage('Scan') {
            steps {
                sh '''
                  go install github.com/securego/gosec/v2/cmd/gosec@latest
                  gosec ./... || true

                  trivy fs --exit-code 0 --severity HIGH,CRITICAL .
                '''
            }
        }

        stage('Build & Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-cred',
                                                  usernameVariable: 'DOCKER_USER',
                                                  passwordVariable: 'DOCKER_PASSWORD')]) {
                    sh '''
                      docker build -t $REGISTRY/$IMAGE:$TAG .
                      echo $DOCKER_PASSWORD | docker login -u $DOCKER_USER --password-stdin
                      docker push $REGISTRY/$IMAGE:$TAG
                    '''
                }
            }
        }

        stage('SonarCloud Analysis') {
            steps {
                withSonarQubeEnv('SonarCloud') {
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

    post {
        always {
            archiveArtifacts artifacts: '*.out, report.xml, ginkgo-report.json', allowEmptyArchive: true
        }
    }
}
