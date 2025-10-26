require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Void < Distributions::Base
    distribution :void

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end

        # Hostname in void is set by /etc/runit/core-services/05-misc.sh.
        # Unfortunately, it tries to set it by writing to /proc/sys/kernel/hostname,
        # which an unprivileged container cannot do. We add out own service
        # to set the hostname using /bin/hostname, which uses a syscall that works.
        sv = File.join(
          rootfs,
          'etc/runit/core-services',
          '10-vpsadminos-hostname.sh'
        )

        return unless writable?(sv)

        ErbTemplate.render_to_if_changed(
          'network/void/hostname',
          {},
          sv
        )
      end

      def network(netifs)
        tpl_base = 'network/void'

        cmds = netifs.map do |netif|
          ErbTemplate.render(
            File.join(tpl_base, netif.type.to_s),
            { netif: }
          )
        end

        sv = File.join(
          rootfs,
          'etc/runit/core-services',
          '90-vpsadminos-network.sh'
        )
        File.write(sv, cmds.join("\n")) if writable?(sv)

        generate_netif_rename_rules(netifs)
      end

      protected

      def network_class
        nil
      end
    end

    # See man runit-init
    def stop(_opts)
      with_rootfs do
        next unless Dir.exist?('/etc/runit')

        # Only the existence of the reboot file can trigger reboot
        if File.exist?('/etc/runit/reboot')
          File.new('/etc/runit/reboot', 'w', 0).close
          File.chmod(0, '/etc/runit/reboot')
        end

        File.new('/etc/runit/stopit', 'w', 0o100).close
        File.chmod(0o100, '/etc/runit/stopit')

        nil
      end

      # Run standard stop process
      super
    end

    def apply_hostname
      ct_syscmd(['hostname', ct.hostname.local])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end

    def passwd(opts)
      # Without the -c switch, the password is not set (bug?)
      ret = ct_syscmd(
        %w[chpasswd -c SHA512],
        stdin: "#{opts[:user]}:#{opts[:password]}\n",
        run: true,
        valid_rcs: :all
      )

      return true if ret.success?

      log(:warn, "Unable to set password: #{ret.output}")
    end
  end
end
