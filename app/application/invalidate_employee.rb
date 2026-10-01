module Application
  # Handler de empleado.retirado: un empleado retirado ya no es válido para programar nuevas
  # vacaciones. No borra la fila del registro local, solo la marca inactiva.
  class InvalidateEmployee
    def initialize(employee_registry:, logger:)
      @employee_registry = employee_registry
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
      else
        @logger.warn(
          'employee not found in local registry; nothing invalidated',
          eventId: envelope.id, empleadoId: empleado_id
        )
      end
    end
  end
end
