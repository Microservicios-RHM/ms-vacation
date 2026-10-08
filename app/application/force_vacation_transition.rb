require_relative '../domain/errors'
require_relative '../domain/error_codes'

module Application
  # Respaldo manual del scheduler, pensado para la sustentación: dispara la misma transición y el
  # mismo evento que dispararía el paso del tiempo, sin esperar al cambio de día. No es un atajo
  # que salte reglas: si el período no está en el estado de origen correcto, falla igual.
  class ForceVacationTransition
    def initialize(vacation_repository:, advance_vacation_periods:)
      @vacation_repository = vacation_repository
      @advance_vacation_periods = advance_vacation_periods
    end

    def start(id)
      period = @vacation_repository.start_now(id)
      raise_not_startable(id) unless period

      @advance_vacation_periods.start_now(period)
      period
    end

    def finish(id)
      period = @vacation_repository.finish_now(id)
      raise_not_finishable(id) unless period

      @advance_vacation_periods.finish_now(period)
      period
    end

    private

    def raise_not_startable(id)
      raise Domain::AppError.new(
        "El período #{id} no existe o no está en estado PROGRAMADA",
        status: 409, code: Domain::ErrorCodes::VACATION_ALREADY_STARTED
      )
    end

    def raise_not_finishable(id)
      raise Domain::AppError.new(
        "El período #{id} no existe o no está en estado EN_CURSO",
        status: 409, code: Domain::ErrorCodes::VACATION_ALREADY_STARTED
      )
    end
  end
end
