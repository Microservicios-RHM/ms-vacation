require 'date'

module Application
  # Tarea periódica del scheduler: es lo único en el ecosistema que observa el paso del tiempo.
  # Hasta el Reto 4 un período quedaba PROGRAMADA para siempre; aquí se le da curso y se cierra.
  class AdvanceVacationPeriods
    EVENT_STARTED = 'vacaciones.iniciadas'.freeze
    EVENT_FINISHED = 'vacaciones.finalizadas'.freeze

    # Envoltorio de cada transición. Por defecto no hace nada; en producción (bootstrap.rb) es
    # Infrastructure::Observability::TransitionTracing, que abre el span raíz del Reto 8 para que
    # el evento publicado arrastre su traza hasta auth-service y notificaciones-service. La capa de
    # aplicación no depende de OpenTelemetry.
    module NoTracing
      def self.call(_event_type, _period) = yield
    end

    def initialize(vacation_repository:, publisher:, logger:, transition_tracing: NoTracing)
      @vacation_repository = vacation_repository
      @publisher = publisher
      @logger = logger
      @transition_tracing = transition_tracing
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
        @transition_tracing.call(type, period) { publish_transition(period, type) }
      end
    end

    def publish_transition(period, type)
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
