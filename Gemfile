source 'https://rubygems.org'

ruby '>= 3.3'

gem 'sinatra', '~> 4.1'
gem 'puma', '~> 6.4'
gem 'rackup', '~> 2.1'
gem 'pg', '~> 1.5'
gem 'bunny', '~> 2.23'
gem 'connection_pool', '~> 2.4'
gem 'dotenv', '~> 3.1'

group :test do
  gem 'rspec', '~> 3.13'
  gem 'rack-test', '~> 2.1'
  # Reto 6: reportes estándar para el pipeline del Reto 7 (JUnit XML para Jenkins, Cobertura XML
  # para SonarQube).
  gem 'rspec_junit_formatter', '~> 0.6'
  gem 'simplecov', '~> 0.22', require: false
  gem 'simplecov-cobertura', '~> 3.0', require: false
end
