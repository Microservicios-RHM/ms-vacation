require 'rack/test'
require 'date'
require 'json'
require_relative '../../../app/infrastructure/http/app'
require_relative '../../../app/application/schedule_vacation'
require_relative '../../../app/application/get_vacation'
require_relative '../../../app/application/list_vacations'
require_relative '../../../app/application/cancel_vacation'
require_relative '../../support/fake_vacation_repository'
require_relative '../../support/fake_employee_registry'
require_relative '../../support/fake_publisher'

RSpec.describe Infrastructure::Http::App do
  include Rack::Test::Methods

  let(:vacation_repository) { FakeVacationRepository.new }
  let(:employee_registry) { FakeEmployeeRegistry.new }
  let(:publisher) { FakePublisher.new }

  def app
    Infrastructure::Http::App.configure_app(
      schedule_vacation: Application::ScheduleVacation.new(
        vacation_repository: vacation_repository, employee_registry: employee_registry, publisher: publisher
      ),
      get_vacation: Application::GetVacation.new(vacation_repository: vacation_repository),
      list_vacations: Application::ListVacations.new(vacation_repository: vacation_repository),
      cancel_vacation: Application::CancelVacation.new(vacation_repository: vacation_repository),
      logger: nil
    )
  end

  let(:future_start) { (Date.today + 30).iso8601 }
  let(:future_end) { (Date.today + 45).iso8601 }

  before { employee_registry.mark_valid_if_new('seed-event', 'E001') }

  it 'GET /health responde 200 con el envelope del ecosistema' do
    get '/health'

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body['success']).to be(true)
    expect(body['data']).to eq('status' => 'UP')
  end

  it 'POST /vacaciones programa un período y responde 201 en camelCase' do
    post '/vacaciones', { empleadoId: 'E001', fechaInicio: future_start, fechaFin: future_end }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    expect(last_response.status).to eq(201)
    data = JSON.parse(last_response.body)['data']
    expect(data['empleadoId']).to eq('E001')
    expect(data['estado']).to eq('PROGRAMADA')
  end

  it 'POST /vacaciones responde 400 con fechas incoherentes' do
    post '/vacaciones', { empleadoId: 'E001', fechaInicio: future_start, fechaFin: future_start }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)['error']['code']).to eq('INVALID_DATE_RANGE')
  end

  it 'POST /vacaciones responde 400 con empleado inexistente' do
    post '/vacaciones', { empleadoId: 'NO-EXISTE', fechaInicio: future_start, fechaFin: future_end }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)['error']['code']).to eq('EMPLOYEE_NOT_FOUND')
  end

  it 'POST /vacaciones responde 400 con solapamiento e incluye conflictingPeriod' do
    post '/vacaciones', { empleadoId: 'E001', fechaInicio: future_start, fechaFin: future_end }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    post '/vacaciones', { empleadoId: 'E001', fechaInicio: future_start, fechaFin: future_end }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    expect(last_response.status).to eq(400)
    body = JSON.parse(last_response.body)
    expect(body['error']['code']).to eq('VACATION_OVERLAP')
    expect(body['error']['conflictingPeriod']['empleadoId']).to eq('E001')
  end

  it 'POST /vacaciones responde 400 VALIDATION_ERROR con campos faltantes' do
    post '/vacaciones', { empleadoId: 'E001' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    expect(last_response.status).to eq(400)
    body = JSON.parse(last_response.body)
    expect(body['error']['code']).to eq('VALIDATION_ERROR')
    expect(body['error']['details'].map { |d| d['field'] }).to include('fechaInicio', 'fechaFin')
  end

  it 'POST /vacaciones responde 400 INVALID_JSON con un cuerpo malformado' do
    post '/vacaciones', '{', { 'CONTENT_TYPE' => 'application/json' }

    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)['error']['code']).to eq('INVALID_JSON')
  end

  it 'GET /vacaciones/:id responde 404 cuando no existe' do
    get '/vacaciones/V-9999-9999'

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)['error']['code']).to eq('VACATION_NOT_FOUND')
  end

  it 'GET /vacaciones filtra por empleadoId' do
    post '/vacaciones', { empleadoId: 'E001', fechaInicio: future_start, fechaFin: future_end }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    get '/vacaciones?empleadoId=E001'

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)['data'].size).to eq(1)
  end

  it 'DELETE /vacaciones/:id cancela un período futuro' do
    created = JSON.parse(
      post('/vacaciones', { empleadoId: 'E001', fechaInicio: future_start, fechaFin: future_end }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }).body
    )['data']

    delete "/vacaciones/#{created['id']}"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)['data']['estado']).to eq('CANCELADA')
  end

  it 'responde 404 con el código RESOURCE_NOT_FOUND para rutas desconocidas' do
    get '/no-existe'

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)['error']['code']).to eq('RESOURCE_NOT_FOUND')
  end
end
