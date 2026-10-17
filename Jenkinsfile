pipeline {
    agent any
    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 15, unit: 'MINUTES')
    }
    triggers { pollSCM('H/2 * * * *') }
    stages {
        stage('Test') {
            steps { sh 'docker build --target test -t express-demo-tests .' }
        }
        stage('Build') {
            steps { sh 'APP_IMAGE=express-demo:$GIT_COMMIT docker compose build --pull app' }
        }
        stage('Deploy') {
            steps { sh 'bash ops/deploy.sh express-demo:$GIT_COMMIT' }
        }
    }
    post {
        failure {
            sh 'docker compose ps; docker compose logs --tail=80 app'
        }
    }
}
