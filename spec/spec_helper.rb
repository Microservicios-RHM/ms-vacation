# Sinatra en modo `development` (el default sin RACK_ENV) solo permite Host: localhost/.test/IP
# en su HostAuthorization; Rack::Test envía "example.org" por defecto, lo que da 403. En
# `test`/`production` la lista de hosts permitidos queda vacía, y rack-protection interpreta una
# lista vacía como "sin restricción" — exactamente el comportamiento esperado detrás del API
# Gateway en Docker.
ENV['RACK_ENV'] ||= 'test'

$LOAD_PATH.unshift(File.expand_path('..', __dir__))

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
