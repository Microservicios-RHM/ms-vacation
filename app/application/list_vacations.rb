require_relative '../domain/errors'
require_relative '../domain/error_codes'

module Application
  class ListVacations
    ESTADOS = %w[PROGRAMADA EN_CURSO FINALIZADA CANCELADA].freeze

    def initialize(vacation_repository:)
      @vacation_repository = vacation_repository
    end

    def execute(empleado_id: nil, estado: nil)
      validate_estado!(estado)
      return @vacation_repository.list_by_employee(empleado_id, estado: estado) if empleado_id

      @vacation_repository.list_all(estado: estado)
    end

    private

    def validate_estado!(estado)
      return if estado.nil? || ESTADOS.include?(estado)

      raise Domain::AppError.new(
        "estado debe ser uno de: #{ESTADOS.join(', ')}",
        status: 400, code: Domain::ErrorCodes::VALIDATION_ERROR,
        details: [{ field: 'estado', message: "estado debe ser uno de: #{ESTADOS.join(', ')}" }]
      )
    end
  end
end
