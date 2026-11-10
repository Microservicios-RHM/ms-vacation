require 'json'
require 'stringio'
require 'tempfile'
require 'rack/test'
require 'sinatra/base'
require 'opentelemetry/sdk'
require_relative '../../app/infrastructure/observability/health'
require_relative '../../app/infrastructure/observability/metrics'
require_relative '../../app/infrastructure/observability/message_tracing'
require_relative '../../app/infrastructure/messaging/consumer'
require_relative '../../app/infrastructure/messaging/publisher'
require_relative '../../app/application/advance_vacation_periods'
require_relative '../../app/infrastructure/logging'
require_relative '../../app/infrastructure/scheduler'
require_relative '../support/fake_vacation_repository'
require_relative '../support/fake_publisher'

# SDK de OpenTelemetry en memoria: los spans terminados quedan en EXPORTER para inspeccionarlos.
EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry::SDK.configure do |config|
  config.logger = Logger.new(File::NULL)
  config.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER))
end

RSpec.describe 'Observabilidad (Reto 8)' do
  before { EXPORTER.reset }

  describe Infrastructure::Observability::Health do
    it 'reporta UP cuando todas las dependencias responden' do
      report = described_class.evaluate('vacaciones-service', { database: -> { true }, messageBroker: -> { true } })
      expect(report).to eq(
        status: 'UP', service: 'vacaciones-service', checks: { 'database' => 'UP', 'messageBroker' => 'UP' }
      )
    end

    it 'reporta DOWN si una dependencia falla, lanza un error o no responde a tiempo' do
      report = described_class.evaluate(
        'vacaciones-service',
        { database: -> { raise 'refused' }, messageBroker: -> { false }, slow: -> { sleep 1 }, ok: -> { true } },
        timeout: 0.05
      )
      expect(report[:status]).to eq('DOWN')
      expect(report[:checks]).to eq('database' => 'DOWN', 'messageBroker' => 'DOWN', 'slow' => 'DOWN', 'ok' => 'UP')
    end
  end

  describe Infrastructure::Observability::Metrics do
    include Rack::Test::Methods

    let(:status_file) do
      Tempfile.new('status').tap do |file|
        file.write("Name:\truby\nVmRSS:\t   2048 kB\n")
        file.flush
      end
    end
    let(:metrics) { described_class.new(service: 'vacaciones-service', status_file: status_file.path) }

    def app
      sample = Class.new(Sinatra::Base) do
        get('/vacaciones/:id') { params['id'] == 'V404' ? halt(404) : 'ok' }
        get('/boom') { raise 'kaboom' }
        set :show_exceptions, false
        set :raise_errors, true
      end
      metrics_instance = metrics
      Rack::Builder.new do
        use Infrastructure::Observability::Metrics::Middleware, metrics: metrics_instance
        run sample
      end
    end

    it 'cuenta peticiones y latencia por patrón de ruta y código, sin el id real' do
      get '/vacaciones/V-2026-0001'
      get '/vacaciones/V-2026-0002'
      get '/vacaciones/V404'
      get '/no-existe'
      expect { get '/boom' }.to raise_error('kaboom')

      get '/metrics'
      body = last_response.body
      expect(last_response.headers['content-type']).to include('text/plain')
      expect(body).to include('http_requests_total{service="vacaciones-service",method="GET",route="/vacaciones/:id",status="200"} 2.0')
      expect(body).to include('http_requests_total{service="vacaciones-service",method="GET",route="/vacaciones/:id",status="404"} 1.0')
      expect(body).to include('route="unmatched"')
      expect(body).to include('status="500"')
      expect(body).to include('http_request_duration_seconds_count{service="vacaciones-service",method="GET",route="/vacaciones/:id",status="200"} 2.0')
      expect(body).to include('process_resident_memory_bytes{service="vacaciones-service"} 2097152.0')
      expect(body).to match(/process_cpu_seconds_total\{service="vacaciones-service"\} \d/)
      expect(body).not_to include('V-2026-0001')
    end

    it 'omite la memoria residente si /proc no existe' do
      missing = described_class.new(service: 'vacaciones-service', status_file: '/no/existe')
      expect(missing.render).not_to include('process_resident_memory_bytes{')
    end
  end

  describe Infrastructure::Observability::MessageTracing do
    it 'publica con un span PRODUCER y el consumidor continúa la misma traza' do
      headers = described_class.with_publish_span('rhm.events', 'vacaciones.iniciadas') { |h| h }
      expect(headers['traceparent']).to match(/\A00-\h{32}-\h{16}-01\z/)

      described_class.with_consume_span(headers, 'auth-service', 'vacaciones.iniciadas') { :ok }

      producer, consumer = EXPORTER.finished_spans
      expect(producer.name).to eq('vacaciones.iniciadas publish')
      expect(producer.kind).to eq(:producer)
      expect(consumer.name).to eq('vacaciones.iniciadas process')
      expect(consumer.kind).to eq(:consumer)
      expect(consumer.hex_trace_id).to eq(producer.hex_trace_id)
      expect(consumer.hex_parent_span_id).to eq(producer.hex_span_id)
    end

    it 'agrega traceId y spanId a los logs JSON solo dentro de un span' do
      io = StringIO.new
      logger = Infrastructure::Logger.new(io: io)
      logger.info('fuera de un span')
      span_ids = described_class.tracer.in_span('op') do |span|
        logger.info('dentro de un span', vacacionId: 'V-1')
        span.context.hex_trace_id
      end

      outside, inside = io.string.lines.map { |line| JSON.parse(line) }
      expect(outside).to include('level' => 'INFO', 'service' => 'vacaciones-service', 'message' => 'fuera de un span')
      expect(outside).to have_key('timestamp')
      expect(outside).not_to have_key('traceId')
      expect(inside).to include('traceId' => span_ids, 'vacacionId' => 'V-1')
    end
  end

  describe 'span raíz del scheduler (TransitionTracing)' do
    let(:vacation_repository) { FakeVacationRepository.new }
    let(:publisher) do
      Class.new do
        attr_reader :traceparents

        def initialize = @traceparents = []

        def publish(type:, data:)
          Infrastructure::Observability::MessageTracing.with_publish_span('rhm.events', type) do |headers|
            @traceparents << [data[:id], headers['traceparent']]
          end
        end
      end.new
    end
    let(:logger) { instance_double(Infrastructure::Logger, info: nil) }

    it 'abre una traza raíz por período y el evento publicado cuelga de ella' do
      %w[V-2026-0001 V-2026-0002].each do |id|
        vacation_repository.save(
          Domain::VacationPeriod.new(
            id: id, empleado_id: 'E001', fecha_inicio: '2026-06-10', fecha_fin: '2026-06-20', estado: 'PROGRAMADA'
          )
        )
      end
      Application::AdvanceVacationPeriods.new(
        vacation_repository: vacation_repository, publisher: publisher, logger: logger,
        transition_tracing: Infrastructure::Observability::TransitionTracing
      ).call('2026-06-15')

      roots = EXPORTER.finished_spans.select { |span| span.name == 'scheduler.vacaciones.iniciar' }
      expect(roots.size).to eq(2)
      expect(roots.map { |span| span.attributes['vacaciones.id'] }).to contain_exactly('V-2026-0001', 'V-2026-0002')
      expect(roots).to all(have_attributes(parent_span_id: OpenTelemetry::Trace::INVALID_SPAN_ID))
      expect(roots.map(&:hex_trace_id).uniq.size).to eq(2)

      publishes = EXPORTER.finished_spans.select { |span| span.name == 'vacaciones.iniciadas publish' }
      expect(publishes.map(&:hex_trace_id)).to match_array(roots.map(&:hex_trace_id))
    end

    it 'desde el scheduler solo traza las transiciones, no las consultas de cada pasada' do
      vacation_repository.save(
        Domain::VacationPeriod.new(
          id: 'V-2026-0009', empleado_id: 'E001', fecha_inicio: '2026-06-10', fecha_fin: '2026-06-20', estado: 'PROGRAMADA'
        )
      )
      use_case = Application::AdvanceVacationPeriods.new(
        vacation_repository: vacation_repository, publisher: publisher, logger: logger,
        transition_tracing: Infrastructure::Observability::TransitionTracing
      )
      scheduler = Infrastructure::Scheduler.new(interval_seconds: 60, logger: logger) do
        OpenTelemetry.tracer_provider.tracer('test').in_span('consulta de la pasada') { nil }
        use_case.call('2026-06-15')
      end
      scheduler.send(:run_once)

      names = EXPORTER.finished_spans.map(&:name)
      expect(names).not_to include('consulta de la pasada')
      root = EXPORTER.finished_spans.find { |span| span.name == 'scheduler.vacaciones.iniciar' }
      expect(root.parent_span_id).to eq(OpenTelemetry::Trace::INVALID_SPAN_ID)
      expect(names).to include('vacaciones.iniciadas publish')
    end
  end

  describe Infrastructure::Messaging::Consumer do
    it 'procesa cada mensaje dentro de un span CONSUMER que continúa el traceparent recibido' do
      queue = double('queue', bind: nil)
      captured = nil
      allow(queue).to receive(:subscribe) { |**_opts, &block| captured = block }
      channel = double('channel', prefetch: nil, topic: double('exchange'), queue: queue, ack: nil, nack: nil)
      connection = double('connection', create_channel: channel)
      logger = instance_double(Infrastructure::Logger, info: nil, error: nil)
      consumer = described_class.new(connection: connection, exchange_name: 'rhm.events', queue_name: 'vacaciones', logger: logger)
      handled = []
      consumer.on('empleado.creado') { |envelope| handled << envelope.id }
      consumer.start

      trace_id = '4bf92f3577b34da6a3ce929d0e0e4736'
      body = JSON.generate(id: 'evt-1', type: 'empleado.creado', version: 1, occurredAt: '2026-01-01T00:00:00.000Z',
                           producer: 'empleados-service', data: { id: 'E001' })
      captured.call(
        double('delivery_info', routing_key: 'empleado.creado', delivery_tag: 1),
        double('properties', headers: { 'traceparent' => "00-#{trace_id}-00f067aa0ba902b7-01" }),
        body
      )

      expect(handled).to eq(['evt-1'])
      span = EXPORTER.finished_spans.find { |s| s.name == 'empleado.creado process' }
      expect(span.hex_trace_id).to eq(trace_id)
      expect(span.hex_parent_span_id).to eq('00f067aa0ba902b7')
    end
  end

  it 'el Publisher envía las cabeceras de traza junto al mensaje' do
    exchange = double('exchange')
    allow(exchange).to receive(:publish)
    publisher = Infrastructure::Messaging::Publisher.new(
      connection: double('connection', create_channel: double('channel', topic: exchange)),
      exchange_name: 'rhm.events', producer_name: 'vacaciones-service',
      logger: instance_double(Infrastructure::Logger, info: nil, error: nil)
    )
    publisher.publish(type: 'vacaciones.programadas', data: { id: 'V-1' })

    expect(exchange).to have_received(:publish).with(
      kind_of(String), hash_including(headers: hash_including('traceparent' => /\A00-/))
    )
  end
end
