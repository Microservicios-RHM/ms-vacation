require_relative '../../app/application/invalidate_employee'
require_relative '../../app/infrastructure/messaging/envelope'
require_relative '../../app/infrastructure/logging'
require_relative '../support/fake_employee_registry'
require_relative '../support/fake_vacation_repository'

RSpec.describe Application::InvalidateEmployee do
  let(:employee_registry) { FakeEmployeeRegistry.new }
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, warn: nil) }
  let(:vacation_repository) { FakeVacationRepository.new }
  subject(:handler) do
    described_class.new(
      employee_registry: employee_registry, vacation_repository: vacation_repository, logger: logger
    )
  end

  let(:envelope) do
    Infrastructure::Messaging::Envelope.new(
      id: 'evt-2', type: 'empleado.retirado', version: 1,
      occurred_at: '2026-06-01T10:00:00.000Z', producer: 'empleados-service',
      data: { 'id' => 'E001' }
    )
  end

  it 'invalida a un empleado previamente registrado' do
    employee_registry.mark_valid_if_new('seed-event', 'E001')

    handler.call(envelope)

    expect(employee_registry.valid?('E001')).to be(false)
  end

  it 'advierte sin fallar si el empleado no estaba en el registro' do
    expect(logger).to receive(:warn)

    expect { handler.call(envelope) }.not_to raise_error
  end

  it 'cancela los períodos que aún no habían iniciado' do
    employee_registry.mark_valid_if_new('seed-event', 'E001')
    vacation_repository.save(
      Domain::VacationPeriod.new(
        id: 'V-2026-0001', empleado_id: 'E001', fecha_inicio: '2026-12-01',
        fecha_fin: '2026-12-15', estado: 'PROGRAMADA'
      )
    )

    handler.call(envelope)

    expect(vacation_repository.find_by_id('V-2026-0001').estado).to eq('CANCELADA')
  end

  it 'deja correr los períodos que ya estaban en curso' do
    employee_registry.mark_valid_if_new('seed-event', 'E001')
    vacation_repository.save(
      Domain::VacationPeriod.new(
        id: 'V-2026-0002', empleado_id: 'E001', fecha_inicio: '2026-06-01',
        fecha_fin: '2026-06-30', estado: 'EN_CURSO'
      )
    )

    handler.call(envelope)

    expect(vacation_repository.find_by_id('V-2026-0002').estado).to eq('EN_CURSO')
  end

  it 'no falla cuando el evento es duplicado' do
    employee_registry.already_processed = true

    expect { handler.call(envelope) }.not_to raise_error
  end
end
