require 'date'
require_relative '../../app/application/schedule_vacation'
require_relative '../support/domain_overlap_vacation_repository'
require_relative '../support/fake_employee_registry'
require_relative '../support/fake_publisher'

# Casos borde de las cuatro validaciones de ScheduleVacation. Repositorio, registro de empleados y
# publicador son dobles en memoria: ninguna prueba toca PostgreSQL ni RabbitMQ.
RSpec.describe Application::ScheduleVacation, 'reglas de negocio' do
  let(:vacation_repository) { DomainOverlapVacationRepository.new }
  let(:employee_registry) { FakeEmployeeRegistry.new }
  let(:publisher) { FakePublisher.new }
  subject(:use_case) do
    described_class.new(
      vacation_repository: vacation_repository, employee_registry: employee_registry, publisher: publisher
    )
  end

  let(:today) { Date.today }

  def day(offset)
    (today + offset).iso8601
  end

  def schedule(inicio, fin, empleado_id: 'E001')
    use_case.execute(empleado_id: empleado_id, fecha_inicio: inicio, fecha_fin: fin)
  end

  def expect_rejection(code)
    expect { yield }.to raise_error(Domain::AppError) do |error|
      expect(error.code).to eq(code)
      expect(error.status).to eq(400)
    end
  end

  before do
    employee_registry.mark_valid_if_new('seed-1', 'E001')
    employee_registry.mark_valid_if_new('seed-2', 'E002')
  end

  describe 'fechaFin > fechaInicio' do
    it 'acepta un período de exactamente dos días' do
      expect(schedule(day(10), day(11)).estado).to eq('PROGRAMADA')
    end

    it 'rechaza fechaFin igual a fechaInicio' do
      expect_rejection(Domain::ErrorCodes::INVALID_DATE_RANGE) { schedule(day(10), day(10)) }
    end

    it 'rechaza fechaFin anterior a fechaInicio' do
      expect_rejection(Domain::ErrorCodes::INVALID_DATE_RANGE) { schedule(day(10), day(5)) }
    end
  end

  describe 'rechazo de fechas pasadas' do
    it 'acepta un período que inicia hoy' do
      expect(schedule(day(0), day(3)).fecha_inicio).to eq(day(0))
    end

    it 'rechaza un período que inició ayer' do
      expect_rejection(Domain::ErrorCodes::DATE_IN_THE_PAST) { schedule(day(-1), day(3)) }
    end
  end

  describe 'solapamiento de períodos' do
    before { schedule(day(20), day(30)) }

    it 'rechaza un período que empieza el mismo día en que termina el existente' do
      expect_rejection(Domain::ErrorCodes::VACATION_OVERLAP) { schedule(day(30), day(35)) }
    end

    it 'rechaza un período contenido dentro del existente y devuelve el período en conflicto' do
      expect { schedule(day(22), day(25)) }.to raise_error(Domain::AppError) do |error|
        expect(error.code).to eq(Domain::ErrorCodes::VACATION_OVERLAP)
        expect(error.conflicting_period).to include(fechaInicio: day(20), fechaFin: day(30))
      end
    end

    it 'acepta un período que empieza el día siguiente al fin del existente' do
      expect(schedule(day(31), day(35)).estado).to eq('PROGRAMADA')
    end

    it 'no considera los períodos de otro empleado' do
      expect(schedule(day(22), day(25), empleado_id: 'E002').empleado_id).to eq('E002')
    end

    it 'ignora los períodos cancelados' do
      vacation_repository.periods.each_value { |period| period.estado = 'CANCELADA' }

      expect(schedule(day(22), day(25)).estado).to eq('PROGRAMADA')
    end

    it 'sigue bloqueando cuando el período existente ya está EN_CURSO' do
      vacation_repository.periods.each_value { |period| period.estado = 'EN_CURSO' }

      expect_rejection(Domain::ErrorCodes::VACATION_OVERLAP) { schedule(day(25), day(40)) }
    end
  end

  describe 'empleado inexistente' do
    it 'rechaza un empleado retirado (invalidado por empleado.retirado)' do
      employee_registry.mark_invalid_if_new('retiro-1', 'E002')

      expect_rejection(Domain::ErrorCodes::EMPLOYEE_NOT_FOUND) { schedule(day(10), day(15), empleado_id: 'E002') }
    end
  end

  describe 'orden de las validaciones' do
    it 'reporta fechas incoherentes antes que fechas pasadas' do
      expect_rejection(Domain::ErrorCodes::INVALID_DATE_RANGE) { schedule(day(-5), day(-10)) }
    end

    it 'reporta solapamiento antes que empleado inexistente' do
      schedule(day(20), day(30))
      employee_registry.mark_invalid_if_new('retiro-2', 'E001')

      expect_rejection(Domain::ErrorCodes::VACATION_OVERLAP) { schedule(day(25), day(28)) }
    end

    it 'no persiste ni publica nada cuando una validación falla' do
      expect { schedule(day(10), day(5)) }.to raise_error(Domain::AppError)

      expect(vacation_repository.periods).to be_empty
      expect(publisher.published).to be_empty
    end
  end
end
