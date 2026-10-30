# frozen_string_literal: true

require 'pathname'

module VpsAdmin
  module SchemaExport
    class UnsafeInput < StandardError; end

    # Check these inputs before requiring Bundler, ActiveRecord or any API helper.
    # SpecDbSetup intentionally resets its selected test database, so allowing a
    # caller's connection settings here would make a harmless export destructive.
    class Safety
      CONFIG_FILES = %w[.keep api.rb.example dataset_plans.rb dataset_properties.rb].freeze
      CONNECTION_ENV = %w[DATABASE_URL VPSADMIN_PLUGIN_DIR].freeze

      def initialize(root:, env: ENV)
        @root = Pathname.new(root).realpath
        @env = env
      end

      def check!
        check_environment!
        check_configuration!
        self
      end

      private

      def check_environment!
        names = CONNECTION_ENV + @env.keys.select do |name|
          name.start_with?('VPSADMIN_TEST_DB_', 'BUNDLE_', 'MYSQL_', 'MARIADB_')
        end
        names.each do |name|
          raise UnsafeInput, "Refusing inherited #{name}" if @env.has_key?(name)
        end

        if @env.has_key?('VPSADMIN_PLUGINS') && @env['VPSADMIN_PLUGINS'] != 'all'
          raise UnsafeInput, 'Schema export requires the all-plugin profile'
        end

        return unless @env.has_key?('RACK_ENV') && @env['RACK_ENV'] != 'test'

        raise UnsafeInput, 'Schema export requires RACK_ENV=test or an unset RACK_ENV'
      end

      def check_configuration!
        %w[api plugins].each do |relative|
          path = @root.join(relative)
          raise UnsafeInput, "Refusing symlinked source directory: #{relative}" if path.symlink?
        end

        config = @root.join('api/config')
        raise UnsafeInput, 'Refusing a symlinked API configuration directory' if config.symlink?
        raise UnsafeInput, 'Missing API configuration directory' unless config.directory?

        config.find do |path|
          next if path == config

          raise UnsafeInput, 'Refusing symlinks in API configuration' if path.symlink?
          next if path.directory?

          relative = path.relative_path_from(config).to_s
          next if CONFIG_FILES.include?(relative) && path.file?

          raise UnsafeInput, "Refusing uncontrolled API configuration: #{relative}"
        end

        %w[.bundle/config api/.bundle/config api/plugins].each do |relative|
          path = @root.join(relative)
          raise UnsafeInput, "Refusing local override: #{relative}" if path.exist? || path.symlink?
        end
      end
    end
  end
end
