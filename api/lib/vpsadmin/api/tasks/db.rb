module VpsAdmin::API::Tasks
  class Db < Base
    def seed_file
      require 'json'
      require 'open3'

      file = resolve_seed_file
      ext = File.extname(file)

      raise 'SEED_FILE must include file extension (.rb or .nix)' if ext.empty?

      puts "Seeding #{file}"

      case ext
      when '.rb'
        load(file)
      when '.nix'
        seed_entries = nix_seed_to_array(file)
        seed_database(seed_entries)
      else
        raise "Unsupported seed file extension #{ext}, expected .rb or .nix"
      end
    end

    private

    def resolve_seed_file
      unless ENV['SEED_FILE']
        raise 'SEED_FILE is required and must include file extension'
      end

      if ENV['SEED_FILE'].start_with?('/')
        ENV['SEED_FILE']
      else
        File.join(VpsAdmin::API.root, 'db', 'seeds', ENV['SEED_FILE'])
      end
    end

    def nix_seed_to_array(file)
      stdout, stderr, status =
        Open3.capture3(
          'nix-instantiate',
          '--eval',
          '--json',
          '--strict',
          '--attr',
          'seed',
          file
        )

      unless status.success?
        raise "nix-instantiate failed for #{file}: #{stderr}"
      end

      seed_data = JSON.parse(stdout)
      return seed_data if seed_data.is_a?(Array)

      raise 'Seed data must be an array of { model, records }'
    rescue Errno::ENOENT => e
      raise "nix-instantiate not found when evaluating #{file}: #{e.message}"
    end

    def seed_database(seed_entries)
      environments = {}
      language = Language.find_by(code: 'en') || Language.order(:id).first
      language ||= Language.create!(code: 'en', label: 'English')

      ActiveRecord::Base.transaction do
        seed_entries.each do |entry|
          model_name = entry.fetch('model')
          records = Array(entry.fetch('records', []))

          raise 'Seed entry requires model and records' unless model_name && !records.empty?

          case model_name.to_s
          when 'SysConfig'
            seed_sys_configs(records)
          when 'ClusterResource'
            seed_cluster_resources(records)
          when 'Environment'
            seed_environments(records, environments)
          when 'Location'
            seed_locations(records, environments)
          when 'User'
            seed_users(records, language)
          else
            seed_generic(model_name, records)
          end
        end
      end
    end

    def seed_sys_configs(records)
      records.each do |cfg|
        record = SysConfig.find_or_initialize_by(
          category: cfg.fetch('category'),
          name: cfg.fetch('name')
        )

        record.assign_attributes(
          data_type: cfg.fetch('data_type', 'String'),
          min_user_level: cfg.fetch('min_user_level', 0),
          value: cfg.fetch('value')
        )
        record.save!
      end
    end

    def seed_cluster_resources(records)
      records.each do |res|
        resource_type = res.fetch('resource_type').to_s

        record = ClusterResource.find_or_initialize_by(name: res.fetch('name'))
        record.assign_attributes(
          label: res.fetch('label'),
          min: res.fetch('min'),
          max: res.fetch('max'),
          stepsize: res.fetch('stepsize'),
          resource_type: ClusterResource.resource_types.fetch(resource_type),
          allocate_chain: nil,
          free_chain: nil
        )
        record.save!
      end
    end

    def seed_environments(records, environments)
      records.each do |env|
        environment = Environment.find_or_initialize_by(id: env.fetch('id'))
        environment.assign_attributes(
          label: env.fetch('label'),
          domain: env.fetch('domain'),
          maintenance_lock: env.fetch('maintenance_lock', 0),
          can_create_vps: env.fetch('can_create_vps', false),
          can_destroy_vps: env.fetch('can_destroy_vps', false),
          vps_lifetime: env.fetch('vps_lifetime', 0),
          max_vps_count: env.fetch('max_vps_count', 0),
          user_ip_ownership: env.fetch('user_ip_ownership', false)
        )
        environment.save!

        environments[environment.id] = environment
      end
    end

    def seed_locations(records, environments)
      records.each do |loc|
        environment_id = loc.fetch('environment_id')
        environment = environments[environment_id] || Environment.find(environment_id)

        location = Location.find_or_initialize_by(id: loc.fetch('id'))
        location.assign_attributes(
          label: loc.fetch('label'),
          domain: loc.fetch('domain'),
          description: loc['description'],
          environment: environment,
          remote_console_server: loc.fetch('remote_console_server'),
          has_ipv6: loc.fetch('has_ipv6')
        )
        location.save!
      end
    end

    def seed_users(records, language)
      records.each do |user|
        language_code = user.fetch('language', 'en')

        user_language = Language.find_by(code: language_code) || language

        record = User.find_or_initialize_by(login: user.fetch('login'))
        record.assign_attributes(
          full_name: user.fetch('full_name'),
          email: user.fetch('email'),
          level: user.fetch('level', 0),
          language: user_language,
          enable_basic_auth: user.fetch('enable_basic_auth', true),
          enable_token_auth: user.fetch('enable_token_auth', true),
          password_reset: user.fetch('password_reset', false),
          lockout: user.fetch('lockout', false),
          object_state: user.fetch('object_state', record.object_state || :active)
        )
        password = user['password']
        record.set_password(password) if password
        record.save!
      end
    end

    def seed_generic(model_name, records)
      model_class = model_name.to_s.split('::').inject(Object) do |mod, name|
        mod.const_get(name)
      end

      records.each do |attrs|
        model_class.create!(attrs)
      end
    rescue NameError => e
      raise "Unknown model #{model_name}: #{e.message}"
    end
  end
end
