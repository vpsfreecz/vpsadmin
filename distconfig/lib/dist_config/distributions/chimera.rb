require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Chimera < Distributions::Base
    distribution :chimera

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end
      end

      def install_user_script(content)
        us = UserScript.new(vps_config, content)
        us.install_systemd
        us.write_script
      end

      def network_class
        Network::Ifupdown
      end
    end

    def apply_hostname
      ct_syscmd(['hostname', ct.hostname.local])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end

    def passwd(user, password)
      # Without the -c switch, the password is not set (bug?)
      ret = ct_syscmd(
        %w[chpasswd -c SHA512],
        stdin: "#{user}:#{password}\n",
        run: true,
        valid_rcs: :all
      )

      return true if ret.success?

      log(:warn, "Unable to set password: #{ret.output}")
    end
  end
end
