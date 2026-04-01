# frozen_string_literal: true

require 'active_record'
require 'yaml'
require 'erb'
require 'uri'

module SpecDbSetup
  module_function

  def establish_connection!(db_name_suffix: nil)
    if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
      url = ENV['DATABASE_URL']
      url = with_db_name_suffix(url, db_name_suffix) if db_name_suffix
      ActiveRecord::Base.establish_connection(url)
      return
    end

    yml_path = File.expand_path('../../config/database.yml', __dir__)
    unless File.exist?(yml_path)
      raise <<~MSG
        No test DB configured.
        Set DATABASE_URL or create api/config/database.yml with a 'test:' section.
      MSG
    end

    raw = ERB.new(File.read(yml_path)).result
    cfg = YAML.safe_load(raw, aliases: true)
    test_cfg = cfg.fetch('test') { raise "Missing 'test:' config in #{yml_path}" }
    test_cfg = coerce_adapter(test_cfg)
    test_cfg = with_db_name_suffix(test_cfg, db_name_suffix) if db_name_suffix
    ensure_database_url!(test_cfg)

    ActiveRecord::Base.establish_connection(test_cfg)
  end

  def ensure_database_exists!
    conn_cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    adapter = conn_cfg[:adapter].to_s
    dbname = configured_database_name(conn_cfg)

    raise 'Database name not configured' if dbname.to_s.empty?

    if reset_enabled? && resettable_adapter?(adapter)
      return recreate_database!(conn_cfg, adapter, dbname)
    end

    ActiveRecord::Base.connection.execute('SELECT 1')
  rescue StandardError => e
    msg = e.message.to_s
    can_reset = reset_enabled? && resettable_adapter?(adapter)
    can_create = resettable_adapter?(adapter)
    unknown_db = msg.include?('Unknown database') || msg.include?('does not exist')

    if can_reset && unknown_db
      return recreate_database!(conn_cfg, adapter, dbname)
    end

    raise e unless can_create && unknown_db

    create_database!(conn_cfg, adapter, dbname)
  end

  def recreate_database!(conn_cfg, adapter, dbname)
    base_cfg = conn_cfg.dup
    base_cfg.delete(:database)
    base_cfg.delete(:dbname)
    base_cfg[:database] = 'postgres' if adapter.include?('postgres')

    ActiveRecord::Base.establish_connection(base_cfg)
    quoted = ActiveRecord::Base.connection.quote_table_name(dbname)

    ActiveRecord::Base.connection.execute("DROP DATABASE IF EXISTS #{quoted}")
    ActiveRecord::Base.connection.execute("CREATE DATABASE #{quoted}")

    ActiveRecord::Base.establish_connection(conn_cfg)
  end
  private_class_method :recreate_database!

  def create_database!(conn_cfg, adapter, dbname)
    base_cfg = conn_cfg.dup
    base_cfg.delete(:database)
    base_cfg.delete(:dbname)
    base_cfg[:database] = 'postgres' if adapter.include?('postgres')

    ActiveRecord::Base.establish_connection(base_cfg)
    quoted = ActiveRecord::Base.connection.quote_table_name(dbname)

    if adapter.include?('mysql')
      ActiveRecord::Base.connection.execute("CREATE DATABASE IF NOT EXISTS #{quoted}")
    else
      ActiveRecord::Base.connection.execute("CREATE DATABASE #{quoted}")
    end

    ActiveRecord::Base.establish_connection(conn_cfg)
  end
  private_class_method :create_database!

  def resettable_adapter?(adapter)
    adapter.include?('mysql') || adapter.include?('postgres')
  end
  private_class_method :resettable_adapter?

  def reset_enabled?
    ENV['RACK_ENV'].to_s == 'test'
  end
  private_class_method :reset_enabled?

  def load_schema!
    schema_path = File.expand_path('../../db/schema.rb', __dir__)
    raise "Missing schema file: #{schema_path}" unless File.exist?(schema_path)

    load schema_path
  end

  def seed_minimal_sysconfig!
    seed_key('core', 'api_url', 'http://api.test')
    seed_key('core', 'webauthn_rp_name', 'vpsAdmin Test')
  end

  def seed_minimal_cluster_resources!
    seed_cluster_resource('cpu', 'CPU', 1, 1024, 1)
    seed_cluster_resource('memory', 'Memory', 128, 1_048_576, 1)
    seed_cluster_resource('diskspace', 'Disk space', 1024, 1_048_576, 1)
    seed_cluster_resource('swap', 'Swap', 0, 1_048_576, 1)
    seed_cluster_resource('ipv4', 'IPv4', 0, 1_000_000, 1)
    seed_cluster_resource('ipv4_private', 'IPv4 private', 0, 1_000_000, 1)
    seed_cluster_resource('ipv6', 'IPv6', 0, 1_000_000, 1)
  end

  def seed_key(category, name, value)
    rec = SysConfig.where(category: category.to_s, name: name.to_s).take

    if rec
      rec.update!(value: value) if rec.value.nil? || rec.value.to_s.empty?
    else
      SysConfig.create!(category: category.to_s, name: name.to_s, value: value)
    end
  end

  def seed_cluster_resource(name, label, min, max, stepsize)
    rec = ClusterResource.where(name: name.to_s).take
    attrs = {
      name: name.to_s,
      label: label.to_s,
      min: min,
      max: max,
      stepsize: stepsize,
      resource_type: ClusterResource.resource_types.fetch('numeric')
    }

    if rec
      updates = attrs.reject { |k, v| rec.public_send(k) == v }
      rec.update!(updates) if updates.any?
    else
      ClusterResource.create!(attrs)
    end
  end

  def coerce_adapter(cfg)
    return cfg unless cfg.is_a?(Hash)

    adapter = cfg[:adapter] || cfg['adapter']
    return cfg unless adapter.to_s == 'mysql'

    cfg = cfg.dup
    cfg[:adapter] = 'mysql2' if cfg.has_key?(:adapter)
    cfg['adapter'] = 'mysql2'
    cfg
  end

  def with_db_name_suffix(cfg_or_url, suffix)
    return cfg_or_url if suffix.to_s.empty?

    if cfg_or_url.is_a?(String)
      uri = URI.parse(cfg_or_url)
      dbname = uri.path.sub(%r{\A/}, '')
      raise 'Database name not configured in DATABASE_URL' if dbname.empty?

      uri.path = "/#{dbname}_#{suffix}"
      uri.to_s
    else
      cfg = cfg_or_url.dup
      dbname = configured_database_name(cfg)
      set_configured_database_name(cfg, "#{dbname}_#{suffix}")
    end
  end
  private_class_method :with_db_name_suffix

  def ensure_database_url!(cfg)
    return if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
    return unless cfg.is_a?(Hash)

    adapter = (cfg[:adapter] || cfg['adapter']).to_s
    adapter = 'mysql2' if adapter == 'mysql'
    return unless %w[mysql2 postgres postgresql].include?(adapter)

    user = cfg[:username] || cfg['username']
    pass = cfg[:password] || cfg['password']
    host = cfg[:host] || cfg['host'] || 'localhost'
    port = cfg[:port] || cfg['port']
    dbname = configured_database_name(cfg)
    return if dbname.to_s.empty?

    scheme = adapter == 'postgres' ? 'postgresql' : adapter
    auth = user ? user.to_s.dup : nil
    auth << ":#{pass}" if auth && pass
    hostpart = host.to_s
    hostpart += ":#{port}" if port

    url = "#{scheme}://"
    url << "#{auth}@" if auth
    url << hostpart
    url << "/#{dbname}"

    ENV['DATABASE_URL'] = url
  end

  def configured_database_name(cfg)
    if cfg.has_key?(:database)
      cfg[:database]
    elsif cfg.has_key?('database')
      cfg['database']
    else
      raise 'Database name not configured'
    end
  end
  private_class_method :configured_database_name

  def set_configured_database_name(cfg, dbname)
    if cfg.has_key?(:database)
      cfg[:database] = dbname
    elsif cfg.has_key?('database')
      cfg['database'] = dbname
    else
      raise 'Database name not configured'
    end

    cfg
  end
  private_class_method :set_configured_database_name
end
