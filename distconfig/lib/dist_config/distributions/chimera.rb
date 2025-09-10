require 'dist_config/distributions/debian'

module DistConfig
  class Distributions::Chimera < Distributions::Debian
    distribution :chimera

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
