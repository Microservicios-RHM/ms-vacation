module Application
  # Handler de empleado.retirado: un empleado retirado ya no es válido para programar nuevas
  # vacaciones. No borra la fila del registro local, solo la marca inactiva, y cancela los
  # períodos que aún no habían comenzado.
  class InvalidateEmployee
    def initialize(employee_registry:, vacation_repository:, logger:)
      @employee_registry = employee_registry
      @vacation_repository = vacation_repository
      @logger = logger
    end

    def call(envelope)
      empleado_id = envelope.data['id']
      was_new, found = @employee_registry.mark_invalid_if_new(envelope.id, empleado_id)

      unless was_new
        @logger.info('duplicate event ignored', eventId: envelope.id, eventType: envelope.type)
        return
      end

      if found
        @logger.info('employee invalidated for scheduling', eventId: envelope.id, empleadoId: empleado_id)
        cancel_scheduled_periods(empleado_id, envelope.id)
      else
        @logger.warn(
          'employee not found in local registry; nothing invalidated',
          eventId: envelope.id, empleadoId: empleado_id
        )
      end
    end

    private

    # Solo los PROGRAMADA. Un período EN_CURSO se deja terminar: su vacaciones.finalizadas es lo
    # que auth-service necesita para cerrar el ciclo, y ahí comprueba que la cuenta quedó con baja
    # permanente y no la reactiva.
    def cancel_scheduled_periods(empleado_id, event_id)
      cancelled = @vacation_repository.cancel_scheduled_for_employee(empleado_id)
      return if cancelled.empty?

      @logger.info(
        'scheduled vacation periods cancelled after retirement',
        eventId: event_id, empleadoId: empleado_id, cancelados: cancelled.map(&:id)
      )
    end
  end
end
