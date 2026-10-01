require_relative '../../app/application/get_vacation'
require_relative '../support/fake_vacation_repository'

RSpec.describe Application::GetVacation do
  let(:vacation_repository) { FakeVacationRepository.new }
  subject(:use_case) { described_class.new(vacation_repository: vacation_repository) }

  it 'retorna el período cuando existe' do
    saved = vacation_repository.save(
      Domain::VacationPeriod.new(id: 'V-2026-0001', empleado_id: 'E001', fecha_inicio: '2026-06-15', fecha_fin: '2026-06-30', estado: 'PROGRAMADA')
    )

    expect(use_case.execute(saved.id)).to eq(saved)
  end

  it 'lanza VACATION_NOT_FOUND (404) cuando no existe' do
    expect { use_case.execute('V-9999-9999') }.to raise_error(Domain::AppError) do |e|
      expect(e.status).to eq(404)
      expect(e.code).to eq(Domain::ErrorCodes::VACATION_NOT_FOUND)
    end
  end
end
