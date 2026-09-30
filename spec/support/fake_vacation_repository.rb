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

  def list_all
    @periods.values
  end

  def list_by_employee(empleado_id)
    @periods.values.select { |period| period.empleado_id == empleado_id }
  end

  def cancel(id)
    period = @periods[id]
    return nil unless period && period.estado == 'PROGRAMADA'

    period.estado = 'CANCELADA'
    period
  end
end
