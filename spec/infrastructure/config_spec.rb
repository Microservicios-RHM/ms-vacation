require_relative '../../app/infrastructure/config'

RSpec.describe Infrastructure::Config do
  VALID_ENV = {
    'DB_HOST' => 'database-vacaciones', 'DB_NAME' => 'vacations_db',
    'DB_USER' => 'vacations_service', 'DB_PASSWORD' => 'secret',
    'BROKER_URL' => 'amqp://admin:admin@message-broker:5672',
  }.freeze
  KEYS = (VALID_ENV.keys + %w[PORT DB_PORT SCHEDULER_ENABLED SCHEDULER_INTERVAL_SECONDS]).freeze

  around do |example|
    saved = KEYS.to_h { |key| [key, ENV[key]] }
    KEYS.each { |key| ENV.delete(key) }
    VALID_ENV.each { |key, value| ENV[key] = value }
    example.run
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # Aísla la prueba de un .env local del desarrollador.
  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with('.env').and_return(false)
  end

  it 'construye la configuración con los valores por defecto' do
    settings = described_class.load

    expect(settings.port).to eq(8080)
    expect(settings.db_port).to eq(5432)
    expect(settings.scheduler_enabled).to be(true)
    expect(settings.scheduler_interval_seconds).to eq(60)
    expect(settings.database_url).to eq('postgres://vacations_service:secret@database-vacaciones:5432/vacations_db')
  end

  it 'permite bajar el intervalo del scheduler por variable de entorno' do
    ENV['SCHEDULER_INTERVAL_SECONDS'] = '5'

    expect(described_class.load.scheduler_interval_seconds).to eq(5)
  end

  it 'usa el valor por defecto si un entero no es válido' do
    ENV['PORT'] = 'ochenta'

    expect(described_class.load.port).to eq(8080)
  end

  it 'falla al arrancar si falta una variable requerida y las nombra' do
    ENV.delete('DB_PASSWORD')
    ENV['DB_HOST'] = ''

    expect { described_class.load }.to raise_error(Infrastructure::ConfigError, /DB_HOST, DB_PASSWORD/)
  end

  it 'rechaza una BROKER_URL que no sea amqp' do
    ENV['BROKER_URL'] = 'http://message-broker:5672'

    expect { described_class.load }.to raise_error(Infrastructure::ConfigError, /amqp/)
  end
end
