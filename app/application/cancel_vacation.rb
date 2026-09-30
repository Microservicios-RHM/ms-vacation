require 'date'
require_relative '../domain/errors'
require_relative '../domain/error_codes'

module Application
  class CancelVacation
    def initialize(vacation_repository:)
      @vacation_repository = vacation_repository
    end

    # "Cancela un período que aún no ha iniciado": en este reto no existe un scheduler que
    # transicione PROGRAMADA -> EN_CURSO (eso es el Reto 5), así que "no ha iniciado" se decide
    # comparando fechaInicio contra hoy, no solo el campo estado.
    def execute(id)
      period = @vacation_repository.find_by_id(id)
      unless period
        raise Domain::AppError.new(
          "El período de vacaciones con id #{id} no existe",
          status: 404, code: Domain::ErrorCodes::VACATION_NOT_FOUND
        )
      end

      if period.estado != 'PROGRAMADA' || period.fecha_inicio <= Date.today.iso8601
        raise Domain::AppError.new(
          'No se puede cancelar un período que ya inició o que no está PROGRAMADA',
          status: 400, code: Domain::ErrorCodes::VACATION_ALREADY_STARTED
        )
      end

      @vacation_repository.cancel(id) || raise(
        Domain::AppError.new(
          'No se puede cancelar un período que ya inició o que no está PROGRAMADA',
          status: 400, code: Domain::ErrorCodes::VACATION_ALREADY_STARTED
        )
      )
    end
  end
end
