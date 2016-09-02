module VpsAdmind::Utils
  module Iptables
    # @param ver [Integer] 4 or 6 for IPv4 and IPv6
    # @param cmd_opts [Hash,Array,String] options for the iptables command
    # @param opts [Hash] options, unhandled options are passed to `syscmd2`
    # @option opts [Boolean] sync synchronize with firewall's mutex
    # @option opts [Integer] tries number of tries if iptables fails with temporary error
    def iptables(ver, cmd_opts, opts = {})
      opts[:sync] = true unless opts.has_key?(:sync)
      opts[:tries] ||= 3
      options = []

      if cmd_opts.instance_of?(Hash)
        cmd_opts.each do |k, v|
          k = k.to_s
          options << "#{k.start_with?("-") ? "" : (k.length > 1 ? "--" : "-")}#{k}#{v ? " " : ""}#{v}"
        end

      elsif cmd_opts.instance_of?(Array)
        options = cmd_opts

      else
        options << cmd_opts
      end

      try_cnt = 0
      cmd = Proc.new do
        syscmd2(
            "#{$CFG.get(:bin, ver == 4 ? :iptables : :ip6tables)} #{options.join(" ")}",
            opts
        )
      end

      begin
        if opts[:sync]
          VpsAdmind::Firewall.synchronize { cmd.call }

        else
          cmd.call
        end

      rescue VpsAdmind::CommandFailed => err
        if err.rc == 1 && err.output =~ /Resource temporarily unavailable/
          if try_cnt == opts[:tries]
            log 'Run out of tries'
            raise err
          end

          log "#{err.cmd} failed with error 'Resource temporarily unavailable', retrying in 3 seconds"

          try_cnt += 1
          sleep(3)
          retry

        else
          raise err
        end
      end
    end
  end
end
