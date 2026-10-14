pipeline {
    agent any
    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 15, unit: 'MINUTES')
    }
    triggers { pollSCM('H/2 * * * *') }
    stages {
        stage('Build') {
            steps { sh 'docker compose build --pull app' }
        }
        stage('Deploy') {
            steps { sh 'docker compose up -d --no-build --wait --wait-timeout 90 app' }
        }
    }
    post {
        failure {
            sh 'docker compose ps; docker compose logs --tail=80 app'
        }
    }
}
