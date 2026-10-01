require 'date'
require_relative '../../app/application/cancel_vacation'
require_relative '../support/fake_vacation_repository'

RSpec.describe Application::CancelVacation do
  let(:vacation_repository) { FakeVacationRepository.new }
  subject(:use_case) { described_class.new(vacation_repository: vacation_repository) }

  it 'cancela un período que aún no ha iniciado' do
    future_start = (Date.today + 10).iso8601
    saved = vacation_repository.save(
      Domain::VacationPeriod.new(id: 'V-2026-0001', empleado_id: 'E001', fecha_inicio: future_start, fecha_fin: (Date.today + 20).iso8601, estado: 'PROGRAMADA')
    )

    cancelled = use_case.execute(saved.id)

    expect(cancelled.estado).to eq('CANCELADA')
  end

  it 'rechaza cancelar un período que ya inició' do
    started = vacation_repository.save(
      Domain::VacationPeriod.new(id: 'V-2026-0002', empleado_id: 'E001', fecha_inicio: Date.today.iso8601, fecha_fin: (Date.today + 5).iso8601, estado: 'PROGRAMADA')
    )

    expect { use_case.execute(started.id) }.to raise_error(Domain::AppError) do |e|
      expect(e.status).to eq(400)
      expect(e.code).to eq(Domain::ErrorCodes::VACATION_ALREADY_STARTED)
    end
  end

  it 'lanza VACATION_NOT_FOUND (404) cuando no existe' do
    expect { use_case.execute('V-9999-9999') }.to raise_error(Domain::AppError) do |e|
      expect(e.status).to eq(404)
      expect(e.code).to eq(Domain::ErrorCodes::VACATION_NOT_FOUND)
    end
  end
end
