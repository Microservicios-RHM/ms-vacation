require_relative '../../app/application/force_vacation_transition'
require_relative '../../app/application/advance_vacation_periods'
require_relative '../../app/infrastructure/logging'
require_relative '../support/fake_vacation_repository'
require_relative '../support/fake_publisher'

# El disparo manual es lo que la suite BDD usa para controlar el tiempo: debe producir exactamente la
# misma transición y el mismo evento que el scheduler, y respetar las mismas precondiciones.
RSpec.describe Application::ForceVacationTransition do
  let(:vacation_repository) { FakeVacationRepository.new }
  let(:publisher) { FakePublisher.new }
  let(:logger) { instance_double(Infrastructure::Logger, info: nil) }
  let(:advance) do
    Application::AdvanceVacationPeriods.new(
      vacation_repository: vacation_repository, publisher: publisher, logger: logger
    )
  end
  subject(:force) do
    described_class.new(vacation_repository: vacation_repository, advance_vacation_periods: advance)
  end

  def save(estado)
    vacation_repository.save(
      Domain::VacationPeriod.new(
        id: 'V-2026-0001', empleado_id: 'E001',
        fecha_inicio: '2099-01-10', fecha_fin: '2099-01-20', estado: estado
      )
    )
  end

  describe '#start' do
    it 'pasa un período PROGRAMADA a EN_CURSO sin esperar su fecha y publica vacaciones.iniciadas' do
      save('PROGRAMADA')

      period = force.start('V-2026-0001')

      expect(period.estado).to eq('EN_CURSO')
      expect(publisher.published.map { |event| event[:type] }).to eq(['vacaciones.iniciadas'])
      expect(publisher.published.first[:data]).to include(empleadoId: 'E001', estado: 'EN_CURSO')
    end

    it 'responde 409 si el período ya está en curso, sin publicar nada' do
      save('EN_CURSO')

      expect { force.start('V-2026-0001') }.to raise_error(Domain::AppError) do |error|
        expect(error.status).to eq(409)
        expect(error.code).to eq(Domain::ErrorCodes::VACATION_ALREADY_STARTED)
      end
      expect(publisher.published).to be_empty
    end

    it 'responde 409 si el período no existe' do
      expect { force.start('V-2026-9999') }.to raise_error(Domain::AppError) { |error| expect(error.status).to eq(409) }
    end
  end

  describe '#finish' do
    it 'pasa un período EN_CURSO a FINALIZADA y publica vacaciones.finalizadas' do
      save('EN_CURSO')

      period = force.finish('V-2026-0001')

      expect(period.estado).to eq('FINALIZADA')
      expect(publisher.published.map { |event| event[:type] }).to eq(['vacaciones.finalizadas'])
    end

    it 'no permite finalizar un período que nunca inició' do
      save('PROGRAMADA')

      expect { force.finish('V-2026-0001') }.to raise_error(Domain::AppError) { |error| expect(error.status).to eq(409) }
      expect(vacation_repository.find_by_id('V-2026-0001').estado).to eq('PROGRAMADA')
      expect(publisher.published).to be_empty
    end
  end
end
