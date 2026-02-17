# frozen_string_literal: true

module SpecPlugins
  module_function

  def selected_mode
    mode = normalized_mode
    return :none if mode == 'none'
    return :all if mode.empty? || mode == 'all'

    :list
  end

  def enabled?(plugin_id)
    return false if selected_mode == :none

    plugin_id = plugin_id.to_sym
    registered = VpsAdmin::API::Plugin.registered
    return registered.has_key?(plugin_id) if registered.any?

    allowed = allowed_plugins
    return allowed.include?(plugin_id) if allowed

    selected_mode == :all
  end

  def any_enabled?
    VpsAdmin::API::Plugin.registered.any?
  end

  def migrate_enabled_plugins!
    return if VpsAdmin::API::Plugin.registered.empty?

    ensure_migration_tables!

    VpsAdmin::API::Plugin.registered.each_value do |plugin|
      next unless enabled?(plugin.id)

      plugin.migrate
    end
  end

  def install_rspec_hooks!
    RSpec.configure do |config|
      config.before do |example|
        requires = example.metadata[:requires_plugins]
        if requires
          if requires == true
            skip('requires plugins enabled') unless any_enabled?
          else
            ids = Array(requires).map(&:to_sym)
            skip("requires plugins: #{ids.join(', ')}") unless ids.all? { |id| enabled?(id) }
          end
        end

        without = example.metadata[:without_plugins]
        if without
          ids = Array(without).map(&:to_sym)
          skip("skipped because plugins are enabled: #{ids.join(', ')}") if ids.any? { |id| enabled?(id) }
        end
      end
    end
  end

  def allowed_plugins
    mode = normalized_mode
    return nil if mode.empty? || mode == 'all' || mode == 'none'

    mode.split(',').map(&:strip).reject(&:empty?).map(&:to_sym)
  end
  private_class_method :allowed_plugins

  def normalized_mode
    ENV['VPSADMIN_PLUGINS'].to_s.strip.downcase
  end
  private_class_method :normalized_mode

  def ensure_migration_tables!
    conn = ActiveRecord::Base.connection

    unless conn.data_source_exists?(ActiveRecord::SchemaMigration.table_name)
      ActiveRecord::SchemaMigration.create_table
    end

    return unless defined?(ActiveRecord::InternalMetadata)
    return if conn.data_source_exists?(ActiveRecord::InternalMetadata.table_name)

    ActiveRecord::InternalMetadata.create_table
  end
  private_class_method :ensure_migration_tables!
end

SpecPlugins.install_rspec_hooks!
