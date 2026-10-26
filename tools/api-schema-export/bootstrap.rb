# frozen_string_literal: true

require 'stringio'

module VpsAdmin
  module SchemaExport
    # Follow the metadata catalog's real runtime bootstrap, without importing
    # spec_helper or its network/model stubs. All writes use our new TestDb.
    class Bootstrap
      PLUGINS = %w[monitoring newslog outage_reports payments requests webui].freeze

      def initialize(root:)
        @root = root
      end

      def load
        require File.join(@root, 'tools/test_db')
        # auto_start! reports a connection URL to stderr. Do not copy credentials
        # into an export log, even for this disposable local database.
        connection = silence(:stderr) { VpsAdmin::TestDb.auto_start! }
        ENV['DATABASE_URL'] = connection
        require 'rspec'
        require File.join(@root, 'api/spec/support/db_setup')
        SpecDbSetup.establish_connection!
        SpecDbSetup.ensure_database_exists!
        ActiveRecord::Schema.verbose = false
        ActiveRecord::Migration.verbose = false
        SpecDbSetup.load_schema!
        require File.join(@root, 'api/lib/vpsadmin')
        require File.join(@root, 'api/spec/support/spec_plugins')
        require File.join(@root, 'api/spec/support/spec_seed')
        SpecSeed.seed_language_if_needed!
        SpecDbSetup.seed_minimal_sysconfig!
        SpecDbSetup.seed_minimal_cluster_resources!
        api = VpsAdmin::API.default
        registered = VpsAdmin::API::Plugin.registered.keys.map(&:to_s).sort
        raise UnsafeInput, 'Loaded plugins do not match the full fixture profile' unless registered == PLUGINS

        SpecPlugins.migrate_enabled_plugins!
        SpecSeed.bootstrap!
        api
      end

      private

      def silence(stream)
        original = stream == :stderr ? $stderr : $stdout
        sink = StringIO.new
        stream == :stderr ? $stderr = sink : $stdout = sink
        yield
      ensure
        stream == :stderr ? $stderr = original : $stdout = original
      end
    end
  end
end
