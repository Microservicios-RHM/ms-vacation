require 'connection_pool'
require_relative '../../app/infrastructure/persistence/migrations'
require_relative '../../app/infrastructure/persistence/vacation_repository'
require_relative '../../app/infrastructure/persistence/employee_registry_repository'
require_relative '../support/overlap_cases'
require_relative '../support/postgres_container'

# Prueba de integración: los repositorios reales contra un PostgreSQL real, con el schema creado por
# las migraciones del propio servicio. Detecta lo que las unitarias no ven: SQL inválido, mapeos
# de columnas, CHECK constraints y que la regla de solapamiento en SQL coincida con la del dominio.
RSpec.describe 'Persistencia de vacaciones contra PostgreSQL', :integration do
  pool = nil

  before(:all) do
    pool = ConnectionPool.new(size: 2, timeout: 5) { PG.connect(PostgresContainer.database_url) }
    Infrastructure::Persistence::Migrations.run(pool)
  end

  after(:all) { pool&.shutdown(&:close) }

  let(:repository) { Infrastructure::Persistence::VacationRepository.new(pool) }
  let(:registry) { Infrastructure::Persistence::EmployeeRegistryRepository.new(pool) }

  before do
    pool.with { |conn| conn.exec('TRUNCATE vacaciones, empleados_validos, eventos_procesados') }
  end

  def persist(empleado_id:, fecha_inicio:, fecha_fin:)
    repository.save(
      Domain::VacationPeriod.new(
        id: repository.next_id, empleado_id: empleado_id,
        fecha_inicio: fecha_inicio, fecha_fin: fecha_fin
      )
    )
  end

  it 'las migraciones son idempotentes' do
    expect(Infrastructure::Persistence::Migrations.run(pool)).to be_empty
  end

  it 'persiste un período y lo recupera con el mismo contenido' do
    saved = persist(empleado_id: 'E001', fecha_inicio: '2026-07-10', fecha_fin: '2026-07-20')

    found = repository.find_by_id(saved.id)
    expect(found.to_h).to include(
      empleadoId: 'E001', fechaInicio: '2026-07-10', fechaFin: '2026-07-20', estado: 'PROGRAMADA'
    )
    expect(found.fecha_creacion).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
  end

  it 'genera identificadores consecutivos con el formato V-AAAA-NNNN' do
    first = repository.next_id
    second = repository.next_id

    expect(first).to match(/\AV-\d{4}-\d{4}\z/)
    expect(second.split('-').last.to_i).to eq(first.split('-').last.to_i + 1)
  end

  it 'el CHECK del schema rechaza un estado fuera del ciclo de vida' do
    saved = persist(empleado_id: 'E001', fecha_inicio: '2026-07-10', fecha_fin: '2026-07-20')

    expect do
      pool.with { |conn| conn.exec_params("UPDATE vacaciones SET estado = 'BORRADA' WHERE id = $1", [saved.id]) }
    end.to raise_error(PG::CheckViolation)
  end

  describe '#find_overlapping coincide con la regla de dominio' do
    before do
      persist(empleado_id: 'E001', fecha_inicio: OverlapCases::EXISTING_START, fecha_fin: OverlapCases::EXISTING_END)
    end

    OverlapCases::TABLE.each do |descripcion, inicio, fin, esperado|
      it "#{esperado ? 'encuentra' : 'no encuentra'} conflicto cuando el nuevo período #{descripcion}" do
        expect(!repository.find_overlapping('E001', inicio, fin).nil?).to be(esperado)
      end
    end

    it 'no cruza períodos entre empleados distintos' do
      expect(repository.find_overlapping('E002', '2026-07-10', '2026-07-20')).to be_nil
    end
  end

  it 'las transiciones del scheduler son atómicas y no se repiten' do
    saved = persist(empleado_id: 'E001', fecha_inicio: '2026-07-10', fecha_fin: '2026-07-20')

    expect(repository.start_due('2026-07-10').map(&:id)).to eq([saved.id])
    expect(repository.start_due('2026-07-10')).to be_empty
    expect(repository.finish_due('2026-07-20')).to be_empty
    expect(repository.finish_due('2026-07-21').map(&:estado)).to eq(['FINALIZADA'])
  end

  it 'un período cancelado deja de bloquear el rango' do
    saved = persist(empleado_id: 'E001', fecha_inicio: '2026-07-10', fecha_fin: '2026-07-20')
    repository.cancel(saved.id)

    expect(repository.find_overlapping('E001', '2026-07-10', '2026-07-20')).to be_nil
  end

  it 'la réplica de empleados deduplica por id de evento e invalida al retirado' do
    expect(registry.mark_valid_if_new('11111111-1111-1111-1111-111111111111', 'E001')).to be(true)
    expect(registry.mark_valid_if_new('11111111-1111-1111-1111-111111111111', 'E001')).to be(false)
    expect(registry.valid?('E001')).to be(true)

    expect(registry.mark_invalid_if_new('22222222-2222-2222-2222-222222222222', 'E001')).to eq([true, true])
    expect(registry.valid?('E001')).to be(false)
  end
end
