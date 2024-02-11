require 'fileutils'
require 'libosctl'
require 'singleton'

module NodeCtld
  # Manages a list of osctl users
  #
  # This class tracks needed osctl users. If a user is needed and does not exist,
  # it is created. As long as the user is not needed, it is destroyed. Each user
  # can be used by one or more VPS.
  class OsCtlUsers
    include Singleton

    class << self
      %i[setup add_pool add_vps remove_vps].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      @pool_users = {}
    end

    def setup
      setup_pool_users
    end

    # Register a new pool
    # @param pool_fs [String]
    def add_pool(pool_fs)
      return if @pool_users.has_key?(pool_fs)

      @pool_users[pool_fs] = PoolUsers.new(pool_fs)
    end

    # Ensure presence of osctl user for a VPS
    # @param pool_fs [String]
    # @param vps_id [Integer]
    # @param user_name [String]
    # @param uidmap [Array<String>]
    # @param gidmap [Array<String>]
    def add_vps(pool_fs:, vps_id:, user_name:, uidmap:, gidmap:)
      @pool_users[pool_fs].add_vps(
        vps_id:,
        user_name:,
        uidmap:,
        gidmap:
      )
    end

    # Remove osctl user requirement, possibly remove the user
    # @param pool_fs [String]
    # @param vps_id [Integer]
    # @param user_name [String]
    def remove_vps(pool_fs:, vps_id:, user_name:)
      @pool_users[pool_fs].remove_vps(vps_id:, user_name:)
    end

    protected

    def setup_pool_users
      RpcClient.run do |rpc|
        rpc.list_pools.each do |pool|
          pu = PoolUsers.new(pool['filesystem'])
          pu.setup(rpc, pool['id'])

          @pool_users[pool['filesystem']] = pu
        end
      end
    end

    class PoolUsers
      include Utils::Pool
      include OsCtl::Lib::Utils::File

      attr_reader :pool_fs

      def initialize(pool_fs)
        @pool_fs = pool_fs
        @pool_name = pool_fs.split('/').first
        @users = {}
        @mutex = Mutex.new
      end

      def setup(rpc, pool_id)
        if config_exist?
          load_config
          return
        end

        rpc.each_vps_user_namespace_map(pool_id) do |vps_map|
          name = vps_map['map_name']
          u = @users[name]

          if u.nil?
            u = User.new_from_rpc(@pool_name, vps_map)
            @users[name] = u
          end

          u.add_vps(vps_map['vps_id'])
        end

        save
      end

      def add_vps(vps_id:, user_name:, uidmap:, gidmap:)
        u = nil

        sync do
          u = @users[user_name]

          if u.nil?
            u = User.new(@pool_name, user_name, uidmap:, gidmap:)
            @users[user_name] = u
          end
        end

        u.add_vps(vps_id)
        save
        nil
      end

      def remove_vps(vps_id:, user_name:)
        u = sync { u = @users[user_name] }
        return if u.nil?

        u.remove_vps(vps_id)
        save
        nil
      end

      protected

      def dump
        save_users = []

        @users.each_value do |u|
          u.sync do
            save_users << u.dump if u.created
          end
        end

        {
          'users' => save_users
        }
      end

      def save
        sync do
          FileUtils.mkdir_p(config_dir)

          regenerate_file(config_path, 0o644) do |new|
            new.puts(OsCtl::Lib::ConfigFile.dump_yaml(dump))
          end
        end
      end

      def load_config
        cfg = OsCtl::Lib::ConfigFile.load_yaml_file(config_path)

        cfg['users'].each do |cfg_user|
          u = User.load_from_config(@pool_name, cfg_user)
          @users[u.name] = u
        end
      end

      def config_exist?
        File.exist?(config_path)
      end

      def config_dir
        @config_dir ||= File.join(
          '/',
          @pool_fs,
          path_to_pool_working_dir(:config),
          'users'
        )
      end

      def config_path
        @config_path ||= File.join(config_dir, 'user-list.yml')
      end

      def sync(&block)
        if @mutex.owned?
          yield
        else
          @mutex.synchronize(&block)
        end
      end
    end

    class User
      include OsCtl::Lib::Utils::Log
      include Utils::System
      include Utils::OsCtl

      def self.new_from_rpc(pool_name, vps_map)
        new(
          pool_name,
          vps_map['map_name'],
          created: true,
          uidmap: vps_map['uidmap'],
          gidmap: vps_map['gidmap']
        )
      end

      def self.load_from_config(pool_name, cfg)
        u = new(
          pool_name,
          cfg['name'],
          created: cfg['created'],
          uidmap: cfg['uidmap'],
          gidmap: cfg['gidmap']
        )

        cfg['vpses'].each do |vps_id|
          u.add_vps(vps_id)
        end

        u
      end

      # @return [String]
      attr_reader :name

      # @return [Boolean]
      attr_reader :created

      def initialize(pool_name, name, uidmap:, gidmap:, created: false)
        @mutex = Mutex.new
        @pool_name = pool_name
        @name = name
        @created = created
        @uidmap = uidmap
        @gidmap = gidmap
        @vpses = {}
      end

      def add_vps(vps_id)
        sync do
          @vpses[vps_id] = true
          create unless @created
        end

        nil
      end

      def remove_vps(vps_id)
        sync do
          @vpses.delete(vps_id)

          if @created && !used?
            begin
              destroy
            rescue SystemCommandFailed => e
              log(:warn, "Unable to remove osctl user #{name}: #{e.message}")
            end
          end
        end

        nil
      end

      def used?
        sync { @vpses.any? }
      end

      def dump
        sync do
          {
            'name' => @name,
            'created' => @created,
            'uidmap' => @uidmap,
            'gidmap' => @gidmap,
            'vpses' => @vpses.keys
          }
        end
      end

      def sync
        if @mutex.owned?
          yield
        else
          @mutex.synchronize(&block)
        end
      end

      def log_type
        "#{@pool_name}:#{@name}"
      end

      protected

      def create
        osctl_pool(@pool_name, %i[user new], @name, { map_uid: @uidmap, map_gid: @gidmap })
        @created = true
      end

      def destroy
        osctl_pool(@pool_name, %i[user del], @name)
        @created = false
      end
    end
  end
end
