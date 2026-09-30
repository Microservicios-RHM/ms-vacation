require_relative '../../app/application/register_valid_employee'
require_relative '../../app/infrastructure/messaging/envelope'
require_relative '../../app/infrastructure/logging'
require_relative '../support/fake_employee_registry'

RSpec.describe Application::RegisterValidEmployee do
  let(:employee_registry) { FakeEmployeeRegistry.new }
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, warn: nil) }
  subject(:handler) { described_class.new(employee_registry: employee_registry, logger: logger) }

  let(:envelope) do
    Infrastructure::Messaging::Envelope.new(
      id: 'evt-1', type: 'empleado.creado', version: 1,
      occurred_at: '2026-03-01T10:00:00.000Z', producer: 'empleados-service',
      data: { 'id' => 'E001' }
    )
  end

  it 'marca al empleado como válido' do
    handler.call(envelope)

    expect(employee_registry.valid?('E001')).to be(true)
  end

  it 'no falla cuando el evento es duplicado' do
    employee_registry.already_processed = true

    expect { handler.call(envelope) }.not_to raise_error
  end
end
