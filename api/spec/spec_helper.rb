# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'bundler/setup'
require 'rspec'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    SpecDbSetup.establish_connection!
    SpecDbSetup.ensure_database_exists!
    SpecDbSetup.load_schema!
    require_relative '../lib/vpsadmin'
    SpecDbSetup.seed_minimal_sysconfig!
    SpecDbSetup.seed_minimal_cluster_resources!
  end
end
