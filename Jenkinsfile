pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                git branch: 'feature',
                    url: 'https://github.com/ErrorMakesClever01/ipt3-food-delivery.git'
            }
        }

        stage('Build Images') {
            steps {
                sh '''
                docker compose build
                '''
            }
        }

        stage('Stop Existing Containers') {
            steps {
                sh '''
                docker compose down || true
                '''
            }
        }

        stage('Deploy') {
            steps {
                sh '''
                docker compose up -d
                '''
            }
        }
        

    post {
        success {
            echo 'Deployment Successful'
        }

        failure {
            echo 'Deployment Failed'
        }
    }
}