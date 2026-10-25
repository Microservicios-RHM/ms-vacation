require 'date'

module Application
  # Tarea periódica del scheduler: es lo único en el ecosistema que observa el paso del tiempo.
  # Hasta el Reto 4 un período quedaba PROGRAMADA para siempre; aquí se le da curso y se cierra.
  class AdvanceVacationPeriods
    EVENT_STARTED = 'vacaciones.iniciadas'.freeze
    EVENT_FINISHED = 'vacaciones.finalizadas'.freeze

    def initialize(vacation_repository:, publisher:, logger:)
      @vacation_repository = vacation_repository
      @publisher = publisher
      @logger = logger
    end

    def call(today = Date.today.iso8601)
      publish_all(@vacation_repository.start_due(today), EVENT_STARTED)
      publish_all(@vacation_repository.finish_due(today), EVENT_FINISHED)
    end

    def start_now(period)
      publish_all([period], EVENT_STARTED)
    end

    def finish_now(period)
      publish_all([period], EVENT_FINISHED)
    end

    private

    def publish_all(periods, type)
      periods.each do |period|
        @publisher.publish(
          type: type,
          data: {
            id: period.id,
            empleadoId: period.empleado_id,
            fechaInicio: period.fecha_inicio,
            fechaFin: period.fecha_fin,
            estado: period.estado,
          }
        )
        @logger.info(
          'vacation period transitioned',
          vacacionId: period.id, empleadoId: period.empleado_id, estado: period.estado
        )
      end
    end
  end
end
