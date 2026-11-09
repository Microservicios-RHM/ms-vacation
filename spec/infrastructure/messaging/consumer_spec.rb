require 'json'
require_relative '../../../app/infrastructure/messaging/consumer'
require_relative '../../../app/infrastructure/logging'

RSpec.describe Infrastructure::Messaging::Consumer do
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, warn: nil, error: nil) }
  subject(:consumer) do
    described_class.new(connection: nil, exchange_name: 'rhm.events', queue_name: 'test.queue', logger: logger)
  end

  let(:body) do
    JSON.generate(
      id: 'evt-1', type: 'empleado.creado', version: 1,
      occurredAt: '2026-03-01T10:00:00.000Z', producer: 'empleados-service', data: { id: 'E001' }
    )
  end

  it 'despacha al handler registrado para la routing key' do
    received = nil
    consumer.on('empleado.creado') { |envelope| received = envelope }

    consumer.route('empleado.creado', body)

    expect(received.id).to eq('evt-1')
    expect(received.data['id']).to eq('E001')
  end

  it 'ignora routing keys sin handler registrado' do
    consumer.on('empleado.creado') { raise 'no debería llamarse' }

    expect { consumer.route('empleado.retirado', body) }.not_to raise_error
  end

  it 'propaga un error si el JSON está malformado' do
    consumer.on('empleado.creado') { raise 'no debería llamarse' }

    expect { consumer.route('empleado.creado', 'esto no es JSON') }.to raise_error(/evento malformado/)
  end

  it 'propaga el error del handler' do
    consumer.on('empleado.creado') { raise 'fallo del handler' }

    expect { consumer.route('empleado.creado', body) }.to raise_error('fallo del handler')
  end

  it 'propaga el contexto de trazas, registra la métrica y confirma el evento' do
    channel = double('channel', ack: nil)
    delivery = double('delivery', routing_key: 'empleado.creado', delivery_tag: 17)
    properties = double('properties', headers: {
                          'traceparent' => '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
                        })
    handled = false
    consumer.on('empleado.creado') { handled = true }
    allow(Infrastructure::Observability).to receive(:observe_event)

    consumer.send(:dispatch, channel, delivery, properties, body)

    expect(handled).to be(true)
    expect(Infrastructure::Observability).to have_received(:observe_event)
      .with('empleado.creado', 'processed')
    expect(channel).to have_received(:ack).with(17)
  end

  it 'registra el fallo y descarta el evento cuando el handler lanza una excepción' do
    channel = double('channel', nack: nil)
    delivery = double('delivery', routing_key: 'empleado.creado', delivery_tag: 18)
    properties = double('properties', headers: nil)
    consumer.on('empleado.creado') { raise 'fallo controlado' }
    allow(Infrastructure::Observability).to receive(:observe_event)

    consumer.send(:dispatch, channel, delivery, properties, body)

    expect(Infrastructure::Observability).to have_received(:observe_event)
      .with('empleado.creado', 'failed')
    expect(logger).to have_received(:error)
      .with('event discarded', routingKey: 'empleado.creado', error: 'fallo controlado')
    expect(channel).to have_received(:nack).with(18, false, false)
  end
end
