require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Guix < Distributions::Base
    distribution :guix

    class Configurator < DistConfig::Configurator
      def set_hostname(_new_hostname, old_hostname: nil)
        log(:warn, 'Unable to apply hostname to Guix System container')
      end

      def network(netifs)
        tpl_base = 'network/guix'

        %w[add del].each do |operation|
          cmds = netifs.map do |netif|
            ErbTemplate.render(
              File.join(tpl_base, netif.type.to_s),
              { netif:, op: operation }
            )
          end

          writable?(File.join(rootfs, "ifcfg.#{operation}")) do |path|
            File.write(path, cmds.join("\n"))
          end
        end
      end

      protected

      def network_class
        nil
      end
    end

    def stop(opts)
      return super unless %i[stop shutdown].include?(opts[:mode])

      # Shepherd gets stuck when it is sent a signal, so shut it down only using
      # halt.
      halt_thread = Thread.new do
        ct_syscmd('halt')
      end

      if halt_thread.join(opts[:timeout]).nil?
        log(:debug, 'Timeout while waiting for graceful shutdown, killing the container')
        halt_thread.terminate
        halt_thread.join
      end

      # The halt may or may not have been successful, kill the container
      # if it is still running
      super(opts.merge(mode: :kill))
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

    def bin_path(_opts)
      with_rootfs do
        File.realpath('/var/guix/profiles/system/profile/bin')
      rescue Errno::ENOENT
        '/bin'
      end
    end
  end
end
