module Application
  # Handler de empleado.creado: alimenta la réplica local de empleados válidos que
  # ScheduleVacation usa para la validación 4 (empleado inexistente), sin acoplarse por REST a
  # empleados-service.
  class RegisterValidEmployee
    def initialize(employee_registry:, logger:)
      @employee_registry = employee_registry
      @logger = logger
    end

    def call(envelope)
      empleado_id = envelope.data['id']
      was_new = @employee_registry.mark_valid_if_new(envelope.id, empleado_id)

      if was_new
        @logger.info('employee registered as valid', eventId: envelope.id, empleadoId: empleado_id)
      else
        @logger.info('duplicate event ignored', eventId: envelope.id, eventType: envelope.type)
      end
    end
  end
end
