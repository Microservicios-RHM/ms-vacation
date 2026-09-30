require_relative '../domain/errors'
require_relative '../domain/error_codes'

module Application
  class GetVacation
    def initialize(vacation_repository:)
      @vacation_repository = vacation_repository
    end

    def execute(id)
      period = @vacation_repository.find_by_id(id)
      return period if period

      raise Domain::AppError.new(
        "El período de vacaciones con id #{id} no existe",
        status: 404, code: Domain::ErrorCodes::VACATION_NOT_FOUND
      )
    end
  end
end
