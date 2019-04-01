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

    # @param pool_fs [String]
    # @param vps_id [Integer]
    def initialize(pool_fs, vps_id)
      @pool_fs = pool_fs
      @vps_id = vps_id

      if exist?
        load
      else
        @network_interfaces = VpsConfig::NetworkInterfaceList.new
      end
    end

    def load
      data = lock { YAML.load_file(path) || {} }

      @network_interfaces = VpsConfig::NetworkInterfaceList.load(data['network_interfaces'] || [])
      @mounts = (data['mounts'] || []).map { |v| VpsConfig::Mount.load(v) }
    end

    def save
      FileUtils.mkpath(File.dirname(path))
      lock { File.write(path, YAML.dump(config)) }
      true
    end

    def exist?
      File.exist?(path)
    end

    protected
    def config
      {
        'network_interfaces' => network_interfaces.save,
      }
    end

    def load
      data = lock { YAML.load_file(path) }

      @network_interfaces = VpsConfig::NetworkInterfaceList.load(data['network_interfaces'])
    end

    def lock
      Filelock(path) { yield }
    end

    def path
      File.join('/', pool_fs, path_to_pool_working_dir(:config), 'vps', "#{vps_id}.yml")
    end
  end
end
