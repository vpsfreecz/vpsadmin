# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'bundler/setup'
require 'rspec'
require 'active_record'
require 'json'
require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'base64'
require 'openssl'

$:.unshift(File.expand_path('../lib', __dir__))

require_relative '../../api/spec/support/db_setup'

SpecDbSetup.establish_connection!(db_name_suffix: 'libnodectld')
SpecDbSetup.ensure_database_exists!
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.verbose = false if defined?(ActiveRecord::Schema)
SpecDbSetup.load_schema!

require 'nodectld/exceptions'
require 'nodectld/utils'
require 'nodectld/db'
require 'nodectld/command'
require 'nodectld/commands/base'

module NodeCtld
  const_set(:NodeBunny, Class.new) unless const_defined?(:NodeBunny)
  const_set(:RpcClient, Class.new) unless const_defined?(:RpcClient)
end

require 'nodectld/pool_status'
require 'nodectld/storage_status'
require 'nodectld/dataset_expander'
OsCtl::Lib::Logger.setup(:none)

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.include NodeCtldSpec::SqlHelpers
  config.include NodeCtldSpec::FixtureHelpers
  config.include NodeCtldSpec::OutputHelpers
  config.include NodeCtldSpec::StorageCommandHelpers

  config.before(:suite) do
    NodeCtldSpec::BaselineSeed.bootstrap!
    NodeCtldSpec::SigningHelpers.install_suite_keypair!
  end

  config.around do |example|
    ActiveRecord::Base.transaction do
      NodeCtldSpec::CfgHelpers.install!(
        node_id: NodeCtldSpec::BaselineSeed.ids.fetch(:node_id),
        public_key_path: NodeCtldSpec::SigningHelpers.public_key_path
      )

      raw_connection = ActiveRecord::Base.connection.raw_connection
      raw_connection.query_options.merge!(as: :hash)

      @shared_db = NodeCtldSpec::SharedConnectionDb.new(raw_connection)

      Thread.current[:spec_on_save_calls] = 0
      Thread.current[:spec_post_save_calls] = 0
      Thread.current[:command] = nil

      example.run
      raise ActiveRecord::Rollback
    ensure
      Thread.current[:spec_on_save_calls] = nil
      Thread.current[:spec_post_save_calls] = nil
      Thread.current[:command] = nil
      $CFG = nil
    end
  end
end
