require 'active_record'
require 'active_record/fixtures'
require 'active_support'
require 'rack/test'
require 'rails'
require 'json'
require 'haveapi/spec/helpers'
require_relative '../lib/vpsadmin'

ENV['RACK_ENV'] = 'test'

# Connect to database
environment = 'test'
configuration = YAML::load(File.open('config/database.yml'))

ActiveRecord::Base.establish_connection(configuration[environment])

# Create database, load schemac
include ActiveRecord::Tasks

DatabaseTasks.create_current('test')
DatabaseTasks.load_schema(:ruby, File.join(File.dirname(__FILE__), '..', 'db', 'schema.rb'))

# Load fixtures
fixtures = ENV['FIXTURES'] ? ENV['FIXTURES'].split(/,/) : Dir.glob(File.join(File.dirname(__FILE__), 'fixtures', '*.yml'))

fixtures.each do |fixture|
  ActiveRecord::FixtureSet.create_fixtures('spec/fixtures', File.basename(fixture, '.*'))
end

HaveAPI.set_module_name(VpsAdmin::API::Resources)
HaveAPI.set_default_authenticate(VpsAdmin::API.authenticate)

# Configure specs
RSpec.configure do |config|
  config.order = 'random'

  config.extend HaveAPI::ApiBuilder
  config.include HaveAPI::SpecMethods

  config.around(:each) do |test|
    ActiveRecord::Base.transaction do
      test.run
      raise ActiveRecord::Rollback
    end
  end
end
