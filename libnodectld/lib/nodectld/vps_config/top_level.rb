require 'filelock'
require 'fileutils'

module NodeCtld
  class VpsConfig::TopLevel
    include Utils::Pool

    # @return [String]
    attr_reader :pool_fs

    # @return [Integer]
    attr_reader :vps_id

    # @return [VpsConfig::NetworkInterfaceList]
    attr_reader :network_interfaces

    # @param mounts [Array<VpsConfig::Mount>]
    # @return [Array<VpsConfig::Mount>]
    attr_accessor :mounts

    # @param pool_fs [String]
    # @param vps_id [Integer]
    # @param load [Boolean]
    def initialize(pool_fs, vps_id, load: true)
      @pool_fs = pool_fs
      @vps_id = vps_id

      if load && exist?
        self.load
      else
        @network_interfaces = VpsConfig::NetworkInterfaceList.new
        @mounts = []
      end
    end

    def load
      data = lock do
        begin
          YAML.safe_load(File.read(path)) || {}
        rescue ArgumentError, SystemCallError
          {}
        end
      end

      @network_interfaces = VpsConfig::NetworkInterfaceList.load(data['network_interfaces'] || [])
      @mounts = (data['mounts'] || []).map { |v| VpsConfig::Mount.load(v) }
    end

    def save
      save_to(path)
      true
    end

    def backup
      save_to(backup_path)
    end

    def restore
      lock do
        File.rename(backup_path, path)
        load
      end
    end

    def destroy(backup: true)
      self.backup if backup
      File.rename(path, destroyed_path)
    end

    def exist?
      File.exist?(path)
    end

    def backup_exist?
      File.exist?(backup_path)
    end

    def lock
      if @locked
        yield
      else
        Filelock(path) do
          @locked = true
          ret = yield
          @locked = false
          ret
        end
      end
    end

    protected
    def config
      {
        'network_interfaces' => network_interfaces.save,
        'mounts' => mounts.map(&:to_h),
      }
    end

    def save_to(file)
      FileUtils.mkpath(File.dirname(file))
      lock do
        new_file = "#{file}.new"
        File.write(new_file, YAML.dump(config))
        File.rename(new_file, file)
      end
    end
    def path
      File.join('/', pool_fs, path_to_pool_working_dir(:config), 'vps', "#{vps_id}.yml")
    end

    def backup_path
      "#{path}.backup"
    end

    def destroyed_path
      "#{path}.destroyed"
    end
  end
end
