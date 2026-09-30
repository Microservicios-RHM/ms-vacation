module Domain
  # Catálogo centralizado de códigos de error, igual que ERROR_CODES en ms-employees y las
  # constantes err_code_* en ms-profiles: los controladores nunca escriben el string a mano.
  module ErrorCodes
    VALIDATION_ERROR = 'VALIDATION_ERROR'.freeze
    INVALID_JSON = 'INVALID_JSON'.freeze
    INVALID_DATE_RANGE = 'INVALID_DATE_RANGE'.freeze
    DATE_IN_THE_PAST = 'DATE_IN_THE_PAST'.freeze
    VACATION_OVERLAP = 'VACATION_OVERLAP'.freeze
    EMPLOYEE_NOT_FOUND = 'EMPLOYEE_NOT_FOUND'.freeze
    VACATION_NOT_FOUND = 'VACATION_NOT_FOUND'.freeze
    VACATION_ALREADY_STARTED = 'VACATION_ALREADY_STARTED'.freeze
    INTERNAL_ERROR = 'INTERNAL_ERROR'.freeze
  end
end
