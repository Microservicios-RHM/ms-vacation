require 'time'
require_relative '../../app/domain/vacation_period'

class FakeVacationRepository
  attr_reader :periods

  def initialize
    @periods = {}
    @next_seq = 1
  end

  def next_id
    id = format('V-%<year>d-%<seq>04d', year: Time.now.year, seq: @next_seq)
    @next_seq += 1
    id
  end

  def find_overlapping(empleado_id, fecha_inicio, fecha_fin)
    @periods.values.find do |period|
      period.empleado_id == empleado_id &&
        %w[PROGRAMADA EN_CURSO].include?(period.estado) &&
        period.fecha_inicio <= fecha_fin && period.fecha_fin >= fecha_inicio
    end
  end

  def save(period)
    saved = period.dup
    saved.fecha_creacion ||= Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
    @periods[saved.id] = saved
    saved
  end

  def find_by_id(id)
    @periods[id]
  end

  def list_all(estado: nil)
    filter(@periods.values, estado)
  end

  def list_by_employee(empleado_id, estado: nil)
    filter(@periods.values.select { |period| period.empleado_id == empleado_id }, estado)
  end

  def start_due(today)
    transition_all('PROGRAMADA', 'EN_CURSO') { |period| period.fecha_inicio <= today }
  end

  def finish_due(today)
    transition_all('EN_CURSO', 'FINALIZADA') { |period| period.fecha_fin < today }
  end

  def start_now(id)
    transition_all('PROGRAMADA', 'EN_CURSO') { |period| period.id == id }.first
  end

  def finish_now(id)
    transition_all('EN_CURSO', 'FINALIZADA') { |period| period.id == id }.first
  end

  def cancel_scheduled_for_employee(empleado_id)
    transition_all('PROGRAMADA', 'CANCELADA') { |period| period.empleado_id == empleado_id }
  end

  def cancel(id)
    period = @periods[id]
    return nil unless period && period.estado == 'PROGRAMADA'

    period.estado = 'CANCELADA'
    period
  end

  private

  def filter(periods, estado)
    estado ? periods.select { |period| period.estado == estado } : periods
  end

  def transition_all(from_estado, to_estado)
    @periods.values.select { |period| period.estado == from_estado && yield(period) }
            .each { |period| period.estado = to_estado }
  end
end
