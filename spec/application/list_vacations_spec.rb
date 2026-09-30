require_relative '../../app/application/list_vacations'
require_relative '../support/fake_vacation_repository'

RSpec.describe Application::ListVacations do
  let(:vacation_repository) { FakeVacationRepository.new }
  subject(:use_case) { described_class.new(vacation_repository: vacation_repository) }

  before do
    vacation_repository.save(
      Domain::VacationPeriod.new(id: 'V-2026-0001', empleado_id: 'E001', fecha_inicio: '2026-06-15', fecha_fin: '2026-06-30', estado: 'PROGRAMADA')
    )
    vacation_repository.save(
      Domain::VacationPeriod.new(id: 'V-2026-0002', empleado_id: 'E002', fecha_inicio: '2026-07-01', fecha_fin: '2026-07-10', estado: 'PROGRAMADA')
    )
  end

  it 'lista todos los períodos sin filtro' do
    expect(use_case.execute.map(&:id)).to contain_exactly('V-2026-0001', 'V-2026-0002')
  end

  it 'filtra por empleadoId cuando se provee' do
    expect(use_case.execute(empleado_id: 'E001').map(&:id)).to contain_exactly('V-2026-0001')
  end
end
