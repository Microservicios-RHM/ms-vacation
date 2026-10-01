module Application
  class ListVacations
    def initialize(vacation_repository:)
      @vacation_repository = vacation_repository
    end

    def execute(empleado_id: nil)
      return @vacation_repository.list_by_employee(empleado_id) if empleado_id

      @vacation_repository.list_all
    end
  end
end
