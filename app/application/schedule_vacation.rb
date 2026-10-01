require 'date'
require_relative '../domain/errors'
require_relative '../domain/error_codes'
require_relative '../domain/vacation_period'

module Application
  class ScheduleVacation
    def initialize(vacation_repository:, employee_registry:, publisher:)
      @vacation_repository = vacation_repository
      @employee_registry = employee_registry
      @publisher = publisher
    end

    # Orden de validaciones tal como lo enumera el enunciado: fechas incoherentes, fechas en el
    # pasado, solapamiento, empleado inexistente.
    def execute(empleado_id:, fecha_inicio:, fecha_fin:)
      validate_date_range!(fecha_inicio, fecha_fin)
      validate_not_in_the_past!(fecha_inicio)
      validate_no_overlap!(empleado_id, fecha_inicio, fecha_fin)
      validate_employee_exists!(empleado_id)

      period = Domain::VacationPeriod.new(
        id: @vacation_repository.next_id,
        empleado_id: empleado_id,
        fecha_inicio: fecha_inicio,
        fecha_fin: fecha_fin,
        estado: 'PROGRAMADA'
      )
      saved = @vacation_repository.save(period)

      # publish() nunca lanza (ver Publisher): un fallo del broker no revierte el período ya
      # persistido ni afecta la respuesta HTTP.
      @publisher.publish(type: 'vacaciones.programadas', data: saved.to_h)

      saved
    end

    private

    def validate_date_range!(fecha_inicio, fecha_fin)
      return if fecha_fin > fecha_inicio

      raise Domain::AppError.new(
        'fechaFin debe ser posterior a fechaInicio',
        status: 400, code: Domain::ErrorCodes::INVALID_DATE_RANGE
      )
    end

    def validate_not_in_the_past!(fecha_inicio)
      return if fecha_inicio >= Date.today.iso8601

      raise Domain::AppError.new(
        'fechaInicio no puede ser anterior a la fecha actual',
        status: 400, code: Domain::ErrorCodes::DATE_IN_THE_PAST
      )
    end

    def validate_no_overlap!(empleado_id, fecha_inicio, fecha_fin)
      conflict = @vacation_repository.find_overlapping(empleado_id, fecha_inicio, fecha_fin)
      return unless conflict

      raise Domain::AppError.new(
        "El empleado #{empleado_id} ya tiene un período que se cruza con el rango solicitado",
        status: 400, code: Domain::ErrorCodes::VACATION_OVERLAP, conflicting_period: conflict.to_h
      )
    end

    def validate_employee_exists!(empleado_id)
      return if @employee_registry.valid?(empleado_id)

      raise Domain::AppError.new(
        "El empleado con id #{empleado_id} no existe",
        status: 400, code: Domain::ErrorCodes::EMPLOYEE_NOT_FOUND
      )
    end
  end
end
