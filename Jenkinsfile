// Pipeline de integración continua de ms-vacation (vacaciones-service: Ruby 3.4 + Sinatra).
//
//   Checkout → Build → Test → SonarQube → Quality Gate → Package → Publish → E2E Tests
//
// Cada etapa que ejecuta pruebas publica su reporte en Jenkins:
//   Test       → Test Result (junit) + Coverage (recordCoverage, Cobertura XML de SimpleCov)
//   E2E Tests  → Test Result (junit) + Cucumber Reports + "Reporte BDD" (HTML) + logs del stack
//
// Convención de estados: una prueba fallida deja el build UNSTABLE (amarillo) y, por
// skipStagesAfterUnstable(), las etapas siguientes no se ejecutan: un servicio con pruebas rotas no
// se empaqueta. Lo que no compila, no pasa el Quality Gate o no construye la imagen es FAILURE (rojo).
//
// Configuración que viene de Jenkins (jenkins/casc.yaml en rhm-database-infrastructure), nunca de
// este archivo: credenciales `sonarqube-token` y `e2e-admin`, y las variables RHM_GIT_BASE_URL,
// RHM_GIT_BRANCH, RHM_REGISTRY, RHM_CI_NETWORK, E2E_BASE_URL y DOCKER_GID.

pipeline {
  agent any

  options {
    skipDefaultCheckout()
    skipStagesAfterUnstable()
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 60, unit: 'MINUTES')
  }

  // Polling como alternativa simple al webhook: Jenkins revisa el repositorio cada ~5 minutos.
  triggers {
    pollSCM('H/5 * * * *')
  }

  environment {
    SERVICE         = 'ms-vacation'
    COMPOSE_SERVICE = 'vacaciones-service'  // nombre del servicio en el docker-compose.yml
    IMAGE           = 'rhm/ms-vacation'
    // Gemas instaladas dentro del volumen de Jenkins: los agentes efímeros las ven por
    // --volumes-from y `bundle install` no descarga todo desde cero en cada build.
    BUNDLE_PATH     = '/var/jenkins_home/caches/bundle/ms-vacation'
    npm_config_cache = '/var/jenkins_home/caches/npm'   // solo para la suite BDD (Node)
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHORT = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
        }
        sh 'git log -1 --format="Commit %h — %s (%an)"'
      }
    }

    stage('Build') {
      agent {
        // Imagen del agente versionada en el repo: Ruby + toolchain de gemas nativas + cliente Docker.
        dockerfile {
          dir 'ci'
          filename 'agent.Dockerfile'
          reuseNode true
        }
      }
      environment {
        HOME = '/tmp'   // el agente corre con el uid de jenkins (1000), sin home en la imagen de Ruby
      }
      steps {
        sh 'bundle install --jobs 4'
        // Ruby no se compila: se verifica la sintaxis de todo app/ y que la aplicación cargue.
        sh 'find app -name "*.rb" -print0 | xargs -0 -n1 ruby -c > /dev/null'
        sh 'bundle exec ruby -e "require \'./app/bootstrap\'" && echo "app/ carga correctamente"'
      }
    }

    stage('Test') {
      agent {
        dockerfile {
          dir 'ci'
          filename 'agent.Dockerfile'
          reuseNode true
          // Las pruebas de integración levantan un PostgreSQL desechable con `docker run` y se
          // conectan a 127.0.0.1:<puerto publicado>: necesitan el socket Docker (y su grupo) y la red
          // del host.
          args "--network host --group-add ${env.DOCKER_GID} -v /var/run/docker.sock:/var/run/docker.sock"
        }
      }
      environment {
        HOME = '/tmp'
        POSTGRES_TEST_HOST = 'host.docker.internal'
      }
      steps {
        // Unitarias + integración, con reportes JUnit XML y Cobertura XML (Reto 6, ver .rspec y
        // spec/coverage_helper.rb). El `|| true` deja llegar al bloque post: es el paso junit, no el
        // código de salida, quien decide el estado del build.
        sh 'bundle exec rspec || echo "rspec terminó con errores: ver la pestaña Test Result"'
      }
      post {
        always {
          junit testResults: 'reports/junit.xml', allowEmptyResults: false
          recordCoverage(
            id: 'coverage',
            name: 'Cobertura (unitarias + integración)',
            tools: [[parser: 'COBERTURA', pattern: 'reports/coverage.xml']],
            sourceDirectories: [[path: '.']],
            sourceCodeRetention: 'EVERY_BUILD'
          )
          // Reporte HTML de SimpleCov, navegable por archivo y línea.
          publishHTML(target: [
            reportDir            : 'reports',
            reportFiles          : 'index.html',
            reportName           : 'Cobertura SimpleCov',
            keepAll              : true,
            alwaysLinkToLastBuild: true,
            allowMissing         : true
          ])
        }
      }
    }

    stage('SonarQube') {
      agent {
        docker {
          image 'sonarsource/sonar-scanner-cli:11'
          reuseNode true
          args "--network ${env.RHM_CI_NETWORK} -e SONAR_USER_HOME=/var/jenkins_home/caches/sonar"
        }
      }
      steps {
        // withSonarQubeEnv inyecta la URL del servidor y el token (credencial sonarqube-token).
        // Proyecto, fuentes y reporte de cobertura: sonar-project.properties.
        withSonarQubeEnv('sonarqube') {
          sh 'sonar-scanner'
        }
      }
    }

    stage('Quality Gate') {
      steps {
        // SonarQube avisa por webhook (http://jenkins:8080/sonarqube-webhook/) cuando termina.
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Package') {
      steps {
        // Dockerfile multi-stage: instala las gemas (sin el grupo test) con la toolchain en una etapa
        // y copia solo el bundle resultante a la imagen final, sin compiladores.
        sh 'docker build --pull=false -t "$IMAGE:$IMAGE_TAG" -t "$IMAGE:latest" .'
        sh 'docker image inspect "$IMAGE:$IMAGE_TAG" --format "Imagen construida: {{index .RepoTags 0}} ({{.Size}} bytes)"'
      }
    }

    stage('Publish') {
      steps {
        sh '''
          docker tag "$IMAGE:$IMAGE_TAG" "$RHM_REGISTRY/$IMAGE:$IMAGE_TAG"
          docker tag "$IMAGE:$IMAGE_TAG" "$RHM_REGISTRY/$IMAGE:latest"
          docker push --quiet "$RHM_REGISTRY/$IMAGE:$IMAGE_TAG"
          docker push --quiet "$RHM_REGISTRY/$IMAGE:latest"
        '''
        echo "📤 Imagen publicada: ${env.RHM_REGISTRY}/${env.IMAGE}:${env.IMAGE_TAG}"
      }
    }

    stage('E2E Tests') {
      environment {
        // Proyecto Compose propio del job: contenedores, red y volúmenes aislados del stack de
        // desarrollo y del E2E de otros servicios (ver ci/docker-compose.e2e.yml).
        COMPOSE_PROJECT_NAME = "rhm-e2e-${env.SERVICE}"
        COMPOSE_FILE         = 'docker-compose.yml:ci/docker-compose.e2e.yml:../service-under-test.yml'
        E2E_ADMIN            = credentials('e2e-admin')
      }
      steps {
        dir('.e2e') { deleteDir() }   // restos de un build anterior
        dir('.e2e') {
          // El stack completo: infraestructura + los demás microservicios + la suite BDD.
          sh '''
            branch_or_default() {
              if git ls-remote --exit-code --heads "$1" "$RHM_GIT_BRANCH" >/dev/null 2>&1; then
                echo "--branch $RHM_GIT_BRANCH"
              fi
            }
            repo="$RHM_GIT_BASE_URL/rhm-database-infrastructure.git"
            git clone --quiet --depth 1 $(branch_or_default "$repo") "$repo" rhm-database-infrastructure
    sh rhm-database-infrastructure/ci/checkout-stack.sh
    sh rhm-database-infrastructure/ci/provision-e2e-secret-volume.sh
          '''
          // El servicio bajo prueba no se reconstruye desde el código: se usa la imagen de Package.
          writeFile file: 'service-under-test.yml', text: """\
            services:
              ${env.COMPOSE_SERVICE}:
                image: ${env.IMAGE}:${env.IMAGE_TAG}
                build: !reset null
            """.stripIndent()

          dir('rhm-database-infrastructure') {
            // ADMIN_* alimenta al auth-service del stack; la suite usa las mismas credenciales.
            sh '''
              docker compose down -v --remove-orphans >/dev/null 2>&1 || true
              ADMIN_USERNAME="$E2E_ADMIN_USR" ADMIN_PASSWORD="$E2E_ADMIN_PSW" \
                docker compose up -d --build --quiet-pull --wait --wait-timeout 300
              docker compose ps --format "table {{.Service}}\t{{.Status}}"
            '''
          }

          // La suite corre en un contenedor efímero dentro de la red del stack. Comparte el workspace
          // con Jenkins (--volumes-from), así que los reportes quedan directamente en .e2e/e2e-tests/reports.
          script {
            docker.image('node:24-alpine').inside("--network ${env.COMPOSE_PROJECT_NAME}-network") {
              dir('e2e-tests') {
                sh 'npm ci --no-audit --no-fund'
                sh '''
                  export BASE_URL="${E2E_BASE_URL:-http://api-gateway:8080}"
                  export E2E_ADMIN_USERNAME="$E2E_ADMIN_USR" E2E_ADMIN_PASSWORD="$E2E_ADMIN_PSW"
                  npm test || echo "Hay escenarios BDD fallidos: ver Cucumber Reports"
                '''
              }
            }
          }
        }
      }
      post {
        always {
          dir('.e2e/rhm-database-infrastructure') {
            // Diagnóstico: sin los logs del stack, un E2E fallido es adivinar.
            sh 'docker compose logs --no-color --timestamps > ../e2e-docker-logs.txt 2>&1 || true'
            // Limpieza: contenedores, red y volúmenes del stack efímero. El próximo build parte de cero.
            sh 'docker compose down -v --remove-orphans || true'
          }
          archiveArtifacts artifacts: '.e2e/e2e-docker-logs.txt', allowEmptyArchive: true

          // Si el stack no llegó a levantar no hay reporte, y junit falla: es intencional, un sistema
          // que no arranca es un fallo, no un "0 pruebas ejecutadas".
          junit testResults: '.e2e/e2e-tests/reports/junit.xml', allowEmptyResults: false
          cucumber(
            jsonReportDirectory: '.e2e/e2e-tests/reports',
            fileIncludePattern: 'cucumber.json',
            buildStatus: 'UNSTABLE',
            reportTitle: 'Escenarios BDD (e2e-tests)'
          )
          publishHTML(target: [
            reportDir            : '.e2e/e2e-tests/reports',
            reportFiles          : 'cucumber.html',
            reportName           : 'Reporte BDD',
            keepAll              : true,
            alwaysLinkToLastBuild: true,
            allowMissing         : true
          ])
        }
      }
    }
  }

  post {
    always {
      // Las etiquetas numeradas ya están en el registry; localmente basta con :latest.
      sh '''
        if [ -n "${IMAGE_TAG:-}" ]; then
          docker image rm "$IMAGE:$IMAGE_TAG" "$RHM_REGISTRY/$IMAGE:$IMAGE_TAG" >/dev/null 2>&1 || true
        fi
      '''
      echo "Pipeline de ${env.SERVICE} finalizado: ${currentBuild.currentResult}"
    }
    success {
      echo '✅ Build, pruebas, Quality Gate, imagen y E2E exitosos'
    }
    unstable {
      echo '⚠️ El código compila pero hay pruebas fallando: ver Test Result / Cucumber Reports'
    }
    failure {
      echo '❌ El pipeline falló: revisar la etapa en rojo'
    }
  }
}
