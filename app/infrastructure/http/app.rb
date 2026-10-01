require 'sinatra/base'
require 'json'
require 'date'
require_relative 'response_helpers'
require_relative '../../domain/errors'
require_relative '../../domain/error_codes'

module Infrastructure
  module Http
    class App < Sinatra::Base
      set :show_exceptions, false
      set :raise_errors, false
      set :dump_errors, false

      helpers ResponseHelpers

      # Nombrado distinto a "build": Sinatra::Base ya define un class method .build (interno,
      # arma la pila de middleware Rack) y un nombre igual lo sobreescribe silenciosamente.
      def self.configure_app(schedule_vacation:, get_vacation:, list_vacations:, cancel_vacation:, logger:)
        set :schedule_vacation, schedule_vacation
        set :get_vacation, get_vacation
        set :list_vacations, list_vacations
        set :cancel_vacation, cancel_vacation
        set :app_logger, logger
        self
      end

      before do
        content_type :json
      end

      get '/health' do
        success_body('Servicio disponible', { status: 'UP' })
      end

      # Montadas bajo /vacaciones (no en la raíz) para poder vivir detrás del API Gateway sin
      # reescritura de rutas: el Gateway ya proxea /vacaciones/* preservando la ruta. Se
      # registran antes que GET /vacaciones/:id — Sinatra prueba las rutas en el orden en que se
      # definen, así que "docs"/"openapi.json" nunca se interpretan como un :id.
      get '/vacaciones/openapi.json' do
        send_file File.join(__dir__, 'openapi.json'), type: :json
      end

      get '/vacaciones/docs' do
        send_file File.join(__dir__, 'docs.html'), type: 'text/html'
      end

      get '/vacaciones' do
        periods = settings.list_vacations.execute(empleado_id: params['empleadoId'])
        status 200
        success_body('Períodos consultados correctamente', periods.map(&:to_h))
      end

      get '/vacaciones/:id' do
        period = settings.get_vacation.execute(params['id'])
        status 200
        success_body('Período consultado correctamente', period.to_h)
      rescue Domain::AppError => e
        halt e.status, app_error_body(e)
      end

      post '/vacaciones' do
        body = parse_json_body
        details = validate_schedule_request(body)
        halt 400, error_body(400, 'Datos de entrada inválidos', Domain::ErrorCodes::VALIDATION_ERROR, request.path, details: details) if details.any?

        period = settings.schedule_vacation.execute(
          empleado_id: body['empleadoId'],
          fecha_inicio: body['fechaInicio'],
          fecha_fin: body['fechaFin']
        )
        status 201
        success_body('Período de vacaciones programado correctamente', period.to_h)
      rescue Domain::AppError => e
        halt e.status, app_error_body(e)
      end

      delete '/vacaciones/:id' do
        period = settings.cancel_vacation.execute(params['id'])
        status 200
        success_body('Período cancelado correctamente', period.to_h)
      rescue Domain::AppError => e
        halt e.status, app_error_body(e)
      end

      # Deliberadamente NO se usa `not_found do...end`: en Sinatra ese hook intercepta
      # cualquier respuesta con status 404 (incluida un `halt 404` de un error de dominio como
      # VACATION_NOT_FOUND), reemplazando su body por este genérico. Una ruta catch-all al final
      # solo se activa si ninguna ruta anterior coincidió, sin pisar los 404 ya construidos.
      %w[GET POST PUT DELETE PATCH].each do |verb|
        route(verb, '/*') do
          content_type :json
          halt 404, error_body(404, 'Recurso no encontrado', 'RESOURCE_NOT_FOUND', request.path)
        end
      end

      error do
        content_type :json
        settings.app_logger&.error('unhandled error', err: env['sinatra.error']&.message)
        error_body(500, 'Error interno del servidor', Domain::ErrorCodes::INTERNAL_ERROR, request.path)
      end

      private

      def app_error_body(error)
        error_body(
          error.status, error.message, error.code, request.path,
          details: error.details, conflicting_period: error.conflicting_period
        )
      end

      def parse_json_body
        parsed = JSON.parse(request.body.read)
        unless parsed.is_a?(Hash)
          halt 400, error_body(400, 'El cuerpo debe ser un objeto JSON', Domain::ErrorCodes::VALIDATION_ERROR, request.path)
        end
        parsed
      rescue JSON::ParserError
        halt 400, error_body(400, 'El cuerpo no es JSON válido', Domain::ErrorCodes::INVALID_JSON, request.path)
      end

      REQUIRED_FIELDS = %w[empleadoId fechaInicio fechaFin].freeze
      DATE_FIELDS = %w[fechaInicio fechaFin].freeze
      DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/.freeze

      def validate_schedule_request(body)
        details = []

        REQUIRED_FIELDS.each do |field|
          value = body[field]
          details << { field: field, message: "#{field} es obligatorio" } if blank?(value)
        end

        DATE_FIELDS.each do |field|
          value = body[field]
          next if blank?(value)
          next if value.is_a?(String) && value.match?(DATE_FORMAT) && valid_calendar_date?(value)

          details << { field: field, message: "#{field} debe tener el formato YYYY-MM-DD" }
        end

        details
      end

      def blank?(value)
        value.nil? || (value.is_a?(String) && value.strip.empty?)
      end

      def valid_calendar_date?(str)
        Date.iso8601(str)
        true
      rescue ArgumentError
        false
      end
    end
  end
end
