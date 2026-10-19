require 'json'
require_relative '../../../app/infrastructure/messaging/publisher'
require_relative '../../../app/infrastructure/logging'

RSpec.describe Infrastructure::Messaging::Publisher do
  # Dobles de Bunny: la conexión entrega un canal, el canal un exchange topic que registra lo publicado.
  class RecordingExchange
    attr_reader :messages

    def initialize = @messages = []

    def publish(payload, **options)
      @messages << { payload: JSON.parse(payload), options: options }
    end
  end

  let(:exchange) { RecordingExchange.new }
  let(:channel) { double('channel', topic: exchange) }
  let(:connection) { double('connection', create_channel: channel) }
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, error: nil) }
  subject(:publisher) do
    described_class.new(
      connection: connection, exchange_name: 'rhm.events', producer_name: 'vacaciones-service', logger: logger
    )
  end

  it 'publica el envelope del ecosistema con la routing key igual al tipo de evento' do
    publisher.publish(type: 'vacaciones.programadas', data: { id: 'V-2026-0001' })

    message = exchange.messages.first
    expect(message[:options]).to include(routing_key: 'vacaciones.programadas', persistent: true)
    expect(message[:payload]).to include(
      'type' => 'vacaciones.programadas', 'version' => 1, 'producer' => 'vacaciones-service',
      'data' => { 'id' => 'V-2026-0001' }
    )
    expect(message[:payload]['id']).to eq(message[:options][:message_id])
    expect(message[:payload]['occurredAt']).to match(/Z\z/)
  end

  it 'declara el exchange una sola vez y lo reutiliza' do
    expect(connection).to receive(:create_channel).once.and_return(channel)
    expect(channel).to receive(:topic).with('rhm.events', durable: true).once.and_return(exchange)

    2.times { publisher.publish(type: 'vacaciones.programadas', data: {}) }

    expect(exchange.messages.size).to eq(2)
  end

  it 'nunca lanza si el broker falla: registra el error y continúa' do
    allow(connection).to receive(:create_channel).and_raise(StandardError, 'broker caído')

    expect { publisher.publish(type: 'vacaciones.programadas', data: {}) }.not_to raise_error
    expect(logger).to have_received(:error).with('Event publish failed', eventType: 'vacaciones.programadas', error: 'broker caído')
  end
end
