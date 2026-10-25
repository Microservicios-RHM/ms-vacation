require_relative 'fake_vacation_repository'

# Doble del repositorio cuya consulta de solapamiento delega en la regla de dominio
# (VacationPeriod#overlaps?) en lugar de reimplementarla. Así, las pruebas del caso de uso
# ejercitan la misma regla que la tabla de casos de spec/domain, y no una copia dentro del fake.
class DomainOverlapVacationRepository < FakeVacationRepository
  ACTIVE_STATES = %w[PROGRAMADA EN_CURSO].freeze

  def find_overlapping(empleado_id, fecha_inicio, fecha_fin)
    periods.values.find do |period|
      period.empleado_id == empleado_id &&
        ACTIVE_STATES.include?(period.estado) &&
        period.overlaps?(fecha_inicio, fecha_fin)
    end
  end
end
