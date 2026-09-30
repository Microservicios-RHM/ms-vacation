module Domain
  # AppError es el error de dominio con toda la información que la capa HTTP necesita para
  # construir el envelope de error del ecosistema (status, code, y opcionalmente details/
  # conflicting_period para la validación de solapamiento).
  class AppError < StandardError
    attr_reader :status, :code, :details, :conflicting_period

    def initialize(message, status:, code:, details: nil, conflicting_period: nil)
      super(message)
      @status = status
      @code = code
      @details = details
      @conflicting_period = conflicting_period
    end
  end
end
