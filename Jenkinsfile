pipeline {
    agent any

    environment {
        EC2_HOST = "44.213.238.31"
        APP_DIR = "/home/ubuntu/ipt3-food-delivery"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'feature',
                    url: 'https://github.com/ErrorMakesClever01/ipt3-food-delivery.git'
            }
        }

        stage('Run Tests') {
            steps {
                sh '''
                    echo "Running tests..."
                '''
            }
        }

        stage('Build Docker Images') {
            steps {
                sh '''
                    docker compose build
                '''
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

                            sudo docker compose up -d --build

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