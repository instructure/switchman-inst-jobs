#!/usr/bin/env groovy

pipeline {
    agent { label 'docker' }

  environment {
    // Make sure we're ignoring any override files that may be present
    COMPOSE_FILE = "docker-compose.yml"
  }

  stages {
    stage('Test') {
      matrix {
        agent { label 'docker' }
        axes {
          axis {
            name 'RUBY_VERSION'
            values '2.7', '3.0', '3.1', '3.2'
          }
          axis {
            name 'LOCKFILE'
            values 'activerecord-6.1', 'activerecord-7.0', 'Gemfile.lock'
          }
        }
        stages {
          stage('Build') {
            steps {
              // Allow postgres to initialize while the build runs
              sh 'docker-compose up -d postgres'
              sh "docker-compose build --pull --build-arg RUBY_VERSION=${RUBY_VERSION} --build-arg app"
              sh "BUNDLE_LOCKFILE=${LOCKFILE} docker-compose run --rm app bundle exec rake db:drop db:create db:migrate"
              sh "BUNDLE_LOCKFILE=${LOCKFILE} docker-compose run --rm app bundle exec rake"
            }
          }
        }
      }
    }

    stage('Lint') {
      steps {
        sh "docker-compose build --pull"
        sh "docker-compose run --rm app bin/rubocop"
      }
    }

  post {
    cleanup {
      sh 'docker-compose down --remove-orphans --rmi all'
    }
  }
}
