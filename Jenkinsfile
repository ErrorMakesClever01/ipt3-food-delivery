pipeline {
    agent any

    environment {
        EC2_HOST = "44.213.238.31"
        APP_DIR = "/home/ubuntu/ipt3-food-delivery"
        SONAR_HOST_URL = "http://44.213.238.31:9000"
        DOCKER_USERNAME = "pranithaprabhakar"
        FRONTEND_IMAGE = "${DOCKER_USERNAME}/food-frontend"
        BACKEND_IMAGE  = "${DOCKER_USERNAME}/food-backend"
        ADMIN_IMAGE    = "${DOCKER_USERNAME}/food-admin"

    }

    stages {
        stage('SonarQube Analysis') {
            steps {
                script {
                def scannerHome = tool 'SonarScanner'

                withCredentials([
                string(
                    credentialsId: 'SonarQube-Token',
                    variable: 'SONAR_TOKEN'
                )
            ]) {
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                        /var/lib/jenkins/tools/hudson.plugins.sonar.SonarRunnerInstallation/SonarScanner/bin/sonar-scanner \
                        -Dsonar.projectKey=ipt3-project \
                        -Dsonar.projectName="IPT3 Food Delivery" \
                        -Dsonar.sources=. \
                        -Dsonar.host.url=$SONAR_HOST_URL \
                        -Dsonar.login=$SONAR_TOKEN
                        '''
                    }
                }
            }
        }
    }

        stage('Quality Gate') {
            steps {
                timeout(time: 2, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Images') {
            steps {
                    sh """
                    docker build -t ${BACKEND_IMAGE}:latest .
                    docker build -t ${FRONTEND_IMAGE}:latest .
                    docker build -t ${ADMIN_IMAGE}:latest .
                    """
                }
        }

        stage('DockerHub Login') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh '''
                    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
                    '''
                }
            }
        }

        stage('Push Images') {
            steps {
                sh """
                docker push ${BACKEND_IMAGE}:latest
                docker push ${FRONTEND_IMAGE}:latest
                docker push ${ADMIN_IMAGE}:latest
                """
            }
        }

        stage('Deploy to EC2') {
            steps {
                sshagent(credentials: ['ec2-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ubuntu@${EC2_HOST} '
                            cd ${APP_DIR}

                            git checkout feature

                            git pull --no-rebase origin feature

                            sudo docker compose down || true

                            sudo docker pull ${BACKEND_IMAGE}:latest
                            sudo docker pull ${FRONTEND_IMAGE}:latest
                            sudo docker pull ${ADMIN_IMAGE}:latest

                            sudo docker compose up -d

                            sudo docker ps
                            '
                        """
                    }
                }
            }
        }

        post {
            success {
                echo 'Application deployed successfully!!!'
            }

            failure {
                echo 'Pipeline failed'
        }
    }
}
