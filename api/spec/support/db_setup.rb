# frozen_string_literal: true

require 'active_record'
require 'yaml'
require 'erb'

module SpecDbSetup
  module_function

  def establish_connection!
    if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
      ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
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
    ensure_database_url!(test_cfg)

    ActiveRecord::Base.establish_connection(test_cfg)
  end

  def ensure_database_exists!
    conn_cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    adapter = conn_cfg[:adapter].to_s
    dbname = conn_cfg[:database] || conn_cfg[:dbname]

    raise 'Database name not configured' if dbname.to_s.empty?

    ActiveRecord::Base.connection.execute('SELECT 1')
  rescue StandardError => e
    msg = e.message.to_s
    can_create = adapter.include?('mysql') || adapter.include?('postgres')
    unknown_db = msg.include?('Unknown database') || msg.include?('does not exist')

    raise e unless can_create && unknown_db

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
    dbname = cfg[:database] || cfg['database'] || cfg[:dbname] || cfg['dbname']
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
end
