require_relative 'infrastructure/config'
require_relative 'infrastructure/logging'
require_relative 'infrastructure/persistence/database'
require_relative 'infrastructure/persistence/migrations'
require_relative 'infrastructure/persistence/vacation_repository'
require_relative 'infrastructure/persistence/employee_registry_repository'
require_relative 'infrastructure/messaging/connection'
require_relative 'infrastructure/messaging/consumer'
require_relative 'infrastructure/messaging/publisher'
require_relative 'infrastructure/http/app'
require_relative 'application/schedule_vacation'
require_relative 'application/get_vacation'
require_relative 'application/list_vacations'
require_relative 'application/cancel_vacation'
require_relative 'application/register_valid_employee'
require_relative 'application/invalidate_employee'

# Raíz de composición, equivalente a server.ts (ms-employees), main.py (ms-notifications) y
# main.go (ms-profiles): construye las implementaciones concretas y las inyecta en los casos de
# uso, que solo conocen las interfaces de dominio.
module Bootstrap
  def self.build
    settings = Infrastructure::Config.load
    logger = Infrastructure::Logger.new(level: settings.log_level)

    logger.info('Connecting to PostgreSQL', host: settings.db_host, database: settings.db_name)
    pool = Infrastructure::Persistence::Database.connect(settings, logger)

    applied = Infrastructure::Persistence::Migrations.run(pool)
    applied.each { |migration| logger.info('Database migration applied', migration: migration) }
    logger.info('PostgreSQL connection ready')

    vacation_repository = Infrastructure::Persistence::VacationRepository.new(pool)
    employee_registry = Infrastructure::Persistence::EmployeeRegistryRepository.new(pool)

    logger.info(
      'Connecting to RabbitMQ',
      exchange: settings.broker_exchange, queue: settings.broker_queue
    )
    connection = Infrastructure::Messaging::Connection.new(
      url: settings.broker_url,
      max_attempts: settings.broker_connect_max_attempts,
      retry_delay_ms: settings.broker_connect_retry_delay_ms,
      logger: logger
    ).start!

    publisher = Infrastructure::Messaging::Publisher.new(
      connection: connection,
      exchange_name: settings.broker_exchange,
      producer_name: 'vacaciones-service',
      logger: logger
    )

    consumer = Infrastructure::Messaging::Consumer.new(
      connection: connection,
      exchange_name: settings.broker_exchange,
      queue_name: settings.broker_queue,
      logger: logger
    )
    consumer.on(
      'empleado.creado',
      Application::RegisterValidEmployee.new(employee_registry: employee_registry, logger: logger)
    )
    consumer.on(
      'empleado.retirado',
      Application::InvalidateEmployee.new(employee_registry: employee_registry, logger: logger)
    )
    consumer.start

    schedule_vacation = Application::ScheduleVacation.new(
      vacation_repository: vacation_repository, employee_registry: employee_registry, publisher: publisher
    )
    get_vacation = Application::GetVacation.new(vacation_repository: vacation_repository)
    list_vacations = Application::ListVacations.new(vacation_repository: vacation_repository)
    cancel_vacation = Application::CancelVacation.new(vacation_repository: vacation_repository)

    logger.info('Vacations service started', port: settings.port)

    Infrastructure::Http::App.configure_app(
      schedule_vacation: schedule_vacation,
      get_vacation: get_vacation,
      list_vacations: list_vacations,
      cancel_vacation: cancel_vacation,
      logger: logger
    )
  end
end
