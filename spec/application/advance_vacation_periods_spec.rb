require_relative '../../app/application/advance_vacation_periods'
require_relative '../../app/infrastructure/logging'
require_relative '../support/fake_vacation_repository'
require_relative '../support/fake_publisher'

RSpec.describe Application::AdvanceVacationPeriods do
  let(:vacation_repository) { FakeVacationRepository.new }
  let(:publisher) { FakePublisher.new }
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, warn: nil, error: nil) }
  subject(:use_case) do
    described_class.new(
      vacation_repository: vacation_repository, publisher: publisher, logger: logger
    )
  end

  def save(id:, estado:, fecha_inicio:, fecha_fin:, empleado_id: 'E001')
    vacation_repository.save(
      Domain::VacationPeriod.new(
        id: id, empleado_id: empleado_id, fecha_inicio: fecha_inicio,
        fecha_fin: fecha_fin, estado: estado
      )
    )
  end

  it 'inicia los períodos programados cuya fecha de inicio ya llegó' do
    save(id: 'V-2026-0001', estado: 'PROGRAMADA', fecha_inicio: '2026-06-10', fecha_fin: '2026-06-20')

    use_case.call('2026-06-15')

    expect(vacation_repository.find_by_id('V-2026-0001').estado).to eq('EN_CURSO')
    expect(publisher.published.map { |event| event[:type] }).to eq(['vacaciones.iniciadas'])
  end

  it 'no toca los períodos cuya fecha de inicio aún no llega' do
    save(id: 'V-2026-0002', estado: 'PROGRAMADA', fecha_inicio: '2026-07-01', fecha_fin: '2026-07-10')

    use_case.call('2026-06-15')

    expect(vacation_repository.find_by_id('V-2026-0002').estado).to eq('PROGRAMADA')
    expect(publisher.published).to be_empty
  end

  it 'finaliza los períodos en curso cuya fecha de fin ya pasó' do
    save(id: 'V-2026-0003', estado: 'EN_CURSO', fecha_inicio: '2026-06-01', fecha_fin: '2026-06-10')

    use_case.call('2026-06-15')

    expect(vacation_repository.find_by_id('V-2026-0003').estado).to eq('FINALIZADA')
    expect(publisher.published.map { |event| event[:type] }).to eq(['vacaciones.finalizadas'])
  end

  it 'publica el payload del catálogo de eventos' do
    save(id: 'V-2026-0004', estado: 'PROGRAMADA', fecha_inicio: '2026-06-10', fecha_fin: '2026-06-20')

    use_case.call('2026-06-15')

    expect(publisher.published.first[:data]).to eq(
      id: 'V-2026-0004', empleadoId: 'E001', fechaInicio: '2026-06-10',
      fechaFin: '2026-06-20', estado: 'EN_CURSO'
    )
  end

  it 'no vuelve a publicar un período que ya había transicionado' do
    save(id: 'V-2026-0005', estado: 'PROGRAMADA', fecha_inicio: '2026-06-10', fecha_fin: '2026-06-20')

    use_case.call('2026-06-15')
    use_case.call('2026-06-15')

    expect(publisher.published.length).to eq(1)
  end
end
