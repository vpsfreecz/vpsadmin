# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'bundler/setup'
require 'rspec'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
  config.filter_run_excluding :generator unless ENV['RUN_GENERATOR_SPECS'] == '1'

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  config.before(:suite) do
    SpecDbSetup.establish_connection!
    SpecDbSetup.ensure_database_exists!
    SpecDbSetup.load_schema!
    require_relative '../lib/vpsadmin'
    SpecSeed.seed_language_if_needed!
    SpecDbSetup.seed_minimal_sysconfig!
    SpecDbSetup.seed_minimal_cluster_resources!
    ApiAppHelper.app_instance
    SpecPlugins.migrate_enabled_plugins!
    SpecSeed.bootstrap!
    TransactionKeyHelpers.install_encrypted_transaction_key!
  end
end
