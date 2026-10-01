require_relative '../../app/application/invalidate_employee'
require_relative '../../app/infrastructure/messaging/envelope'
require_relative '../../app/infrastructure/logging'
require_relative '../support/fake_employee_registry'

RSpec.describe Application::InvalidateEmployee do
  let(:employee_registry) { FakeEmployeeRegistry.new }
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, warn: nil) }
  subject(:handler) { described_class.new(employee_registry: employee_registry, logger: logger) }

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

  it 'no falla cuando el evento es duplicado' do
    employee_registry.already_processed = true

    expect { handler.call(envelope) }.not_to raise_error
  end
end
