# Se carga antes que spec_helper (ver .rspec): SimpleCov tiene que arrancar antes de que se requiera
# cualquier archivo de app/, o esas líneas no se cuentan.
require 'simplecov'
require 'simplecov-cobertura'
require 'simplecov_json_formatter'

SimpleCov.start do
  coverage_dir 'reports'
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,      # reports/index.html  (para humanos)
    SimpleCov::Formatter::CoberturaFormatter, # reports/coverage.xml (para Jenkins: recordCoverage)
    SimpleCov::Formatter::JSONFormatter,      # reports/coverage.json (para SonarQube)
  ])

  track_files 'app/**/*.rb'
  add_filter '/spec/'

  # Excluidos a propósito: no contienen reglas de negocio, solo cableado o adaptadores a librerías.
  # Probarlos unitariamente inflaría la cobertura sin verificar ningún comportamiento.
  add_filter 'app/bootstrap.rb'                            # raíz de composición
  add_filter 'app/infrastructure/observability/tracing.rb' # configuración global del SDK de OpenTelemetry
  add_filter 'app/infrastructure/logging.rb'               # envoltorio de logger JSON
  add_filter 'app/infrastructure/messaging/connection.rb'  # reintentos de conexión a RabbitMQ
  add_filter 'app/infrastructure/persistence/database.rb'  # reintentos de conexión a PostgreSQL

  add_group 'Dominio', 'app/domain'
  add_group 'Aplicación', 'app/application'
  add_group 'Infraestructura', 'app/infrastructure'

  # Si la cobertura cae por debajo del 70 %, rspec termina con código distinto de cero.
  minimum_coverage 70
end
