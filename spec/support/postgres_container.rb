require 'open3'
require 'pg'

# Equivalente mínimo de Testcontainers con el CLI de Docker: levanta un PostgreSQL 17 desechable
# (la misma imagen que usa el Compose), espera a que acepte conexiones y lo destruye al terminar la
# suite. Se arranca una sola vez y solo si se ejecuta alguna prueba etiquetada :integration, así
# que `rspec --tag ~integration` nunca necesita Docker.
module PostgresContainer
  IMAGE = 'postgres:17-alpine'.freeze
  USER = 'vacations_test'.freeze
  PASSWORD = 'vacations_test'.freeze
  DATABASE = 'vacations_test'.freeze
  MAX_ATTEMPTS = 30
  INTERVAL_SECONDS = 1

  class << self
    def database_url
      @database_url ||= start
    end

    def stop
      return unless @container_id

      Open3.capture3('docker', 'rm', '-f', @container_id)
      @container_id = nil
    end

    private

    def start
      @container_id = docker(
        'run', '-d', '--rm', '--label', 'rhm.test=ms-vacation-integration',
        '-e', "POSTGRES_USER=#{USER}", '-e', "POSTGRES_PASSWORD=#{PASSWORD}", '-e', "POSTGRES_DB=#{DATABASE}",
        '-p', '127.0.0.1::5432', IMAGE
      )
      at_exit { stop }

      host_port = docker('port', @container_id, '5432/tcp').lines.first.strip.split(':').last
      url = "postgres://#{USER}:#{PASSWORD}@127.0.0.1:#{host_port}/#{DATABASE}"
      wait_until_ready(url)
      url
    end

    # Polling, no sleep fijo: termina en cuanto Postgres acepta conexiones TCP. Durante el init la
    # imagen solo escucha por socket Unix, así que un connect exitoso significa servidor definitivo.
    def wait_until_ready(url)
      MAX_ATTEMPTS.times do
        PG.connect(url).close
        return
      rescue PG::Error
        sleep(INTERVAL_SECONDS)
      end
      raise "PostgreSQL de pruebas no respondió tras #{MAX_ATTEMPTS} intentos"
    end

    def docker(*args)
      out, err, status = Open3.capture3('docker', *args)
      raise "docker #{args.first} falló: #{err.strip}" unless status.success?

      out.strip
    end
  end
end
