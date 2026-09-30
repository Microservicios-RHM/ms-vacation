require 'date'
require_relative '../../app/application/schedule_vacation'
require_relative '../support/fake_vacation_repository'
require_relative '../support/fake_employee_registry'
require_relative '../support/fake_publisher'

RSpec.describe Application::ScheduleVacation do
  let(:vacation_repository) { FakeVacationRepository.new }
  let(:employee_registry) { FakeEmployeeRegistry.new }
  let(:publisher) { FakePublisher.new }
  subject(:use_case) do
    described_class.new(
      vacation_repository: vacation_repository, employee_registry: employee_registry, publisher: publisher
    )
  end

  let(:future_start) { (Date.today + 30).iso8601 }
  let(:future_end) { (Date.today + 45).iso8601 }

  before { employee_registry.mark_valid_if_new('seed-event', 'E001') }

  it 'programa un período válido y publica vacaciones.programadas' do
    period = use_case.execute(empleado_id: 'E001', fecha_inicio: future_start, fecha_fin: future_end)

    expect(period.estado).to eq('PROGRAMADA')
    expect(period.empleado_id).to eq('E001')
    expect(period.id).to match(/\AV-\d{4}-\d{4}\z/)

    expect(publisher.published.size).to eq(1)
    expect(publisher.published.first[:type]).to eq('vacaciones.programadas')
    expect(publisher.published.first[:data][:empleadoId]).to eq('E001')
  end

  it 'rechaza fechaFin no posterior a fechaInicio' do
    expect do
      use_case.execute(empleado_id: 'E001', fecha_inicio: future_start, fecha_fin: future_start)
    end.to raise_error(Domain::AppError) { |e| expect(e.code).to eq(Domain::ErrorCodes::INVALID_DATE_RANGE) }
  end

  it 'rechaza fechaInicio en el pasado' do
    past = (Date.today - 5).iso8601
    expect do
      use_case.execute(empleado_id: 'E001', fecha_inicio: past, fecha_fin: future_end)
    end.to raise_error(Domain::AppError) { |e| expect(e.code).to eq(Domain::ErrorCodes::DATE_IN_THE_PAST) }
  end

  it 'rechaza el solapamiento e incluye el período en conflicto' do
    use_case.execute(empleado_id: 'E001', fecha_inicio: future_start, fecha_fin: future_end)

    overlapping_start = (Date.parse(future_start) + 5).iso8601
    overlapping_end = (Date.parse(future_end) + 5).iso8601

    expect do
      use_case.execute(empleado_id: 'E001', fecha_inicio: overlapping_start, fecha_fin: overlapping_end)
    end.to raise_error(Domain::AppError) do |e|
      expect(e.code).to eq(Domain::ErrorCodes::VACATION_OVERLAP)
      expect(e.conflicting_period[:empleadoId]).to eq('E001')
    end
  end

  it 'rechaza un empleado inexistente' do
    expect do
      use_case.execute(empleado_id: 'NO-EXISTE', fecha_inicio: future_start, fecha_fin: future_end)
    end.to raise_error(Domain::AppError) { |e| expect(e.code).to eq(Domain::ErrorCodes::EMPLOYEE_NOT_FOUND) }
  end

  it 'no publica ningún evento cuando una validación falla' do
    expect do
      use_case.execute(empleado_id: 'NO-EXISTE', fecha_inicio: future_start, fecha_fin: future_end)
    end.to raise_error(Domain::AppError)

    expect(publisher.published).to be_empty
  end
end
