require 'libosctl'
require 'fileutils'

module NodeCtld
  class QemuHook
    include OsCtl::Lib::Utils::Log
    include Utils::System

    def self.install
      hook_dir = '/var/lib/libvirt/hooks/qemu.d'
      hook_file = File.join(hook_dir, '10-vpsadmin')
      tmp_file = "#{hook_file}.new"

      FileUtils.mkdir_p(hook_dir)

      File.write(
        tmp_file,
        File.read(File.join(File.dirname(__FILE__), '../../templates/libvirt/qemu_hook.rb'))
      )

      File.chmod(0o555, tmp_file)
      File.rename(tmp_file, hook_file)
    end

    def self.run(args)
      if args.length < 2
        raise ArgumentError, 'Expected at least domain and action arguments'
      end

      new(args).run
    end

    def initialize(args)
      @domain, @action, = args
    end

    def run
      setup_network_interfaces if @action == 'start'
    end

    protected

    def setup_network_interfaces
      VpsConfig.open(@domain) do |cfg|
        cfg.network_interfaces.each do |netif|
          syscmd("ip link set dev #{netif.host_name} down")
          syscmd("ip link set dev #{netif.host_name} address #{netif.host_mac}")
          syscmd("ip link set dev #{netif.host_name} up")

          netif.routes.each do |ip_v, routes|
            routes.each do |r|
              syscmd("ip -#{ip_v} route add #{r.address} #{r.via && "via #{r.via}"}")
            end
          end
        end
      end
    end
  end
end
