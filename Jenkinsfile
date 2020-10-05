#!/usr/bin/env groovy

pipeline {
    agent {
        label 'docker'
    }
    environment {
        COMPOSE_FILE = 'docker-compose.yml'
    }
    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '50'))
        timeout(time: 20, unit: 'MINUTES')
    }
    stages {
        stage('Build') {
            steps {
                sh 'docker-compose pull postgres'
                sh 'docker-compose up -d postgres'
                sh 'docker-compose build --pull app'
            }
        }
        stage('Test') {
            steps {
                sh '''
                    docker-compose run --rm app /bin/bash -l -c \
                        "rvm-exec 2.5 bundle exec rubocop --fail-level autocorrect"
                    docker-compose run --name coverage app
                '''
            }
            post {
                always {
                    sh 'docker cp coverage:/app/coverage .'
                    sh 'docker-compose down --rmi=all --volumes --remove-orphans'

                    publishHTML target: [
                      allowMissing: false,
                      alwaysLinkToLastBuild: false,
                      keepAll: true,
                      reportDir: 'coverage',
                      reportFiles: 'index.html',
                      reportName: 'Coverage Report'
                    ]
                }
            }
        }
    }
}
