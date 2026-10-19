require_relative '../../app/infrastructure/scheduler'
require_relative '../../app/infrastructure/logging'

RSpec.describe Infrastructure::Scheduler do
  let(:logger) { instance_double(Infrastructure::Logger, info: nil, error: nil) }

  it 'ejecuta la tarea en cada pasada' do
    calls = 0
    scheduler = described_class.new(interval_seconds: 60, logger: logger) { calls += 1 }

    2.times { scheduler.send(:run_once) }

    expect(calls).to eq(2)
  end

  it 'una pasada que falla no detiene el scheduler: registra el error y sigue' do
    scheduler = described_class.new(interval_seconds: 60, logger: logger) { raise 'BD caída' }

    expect { scheduler.send(:run_once) }.not_to raise_error
    expect(logger).to have_received(:error).with('Vacation scheduler run failed', error: 'BD caída')
  end

  it 'arranca un hilo en segundo plano y lo detiene' do
    scheduler = described_class.new(interval_seconds: 60, logger: logger) { nil }

    expect(scheduler.start).to be(scheduler)
    thread = scheduler.instance_variable_get(:@thread)
    expect(thread).to be_alive

    scheduler.stop
    expect(thread.join(1)).not_to be_nil
    expect(logger).to have_received(:info).with('Vacation scheduler started', intervalSeconds: 60)
  end
end
