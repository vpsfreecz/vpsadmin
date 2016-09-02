module VpsAdmind::Utils
  module Iptables
    def iptables(ver, opts, valid_rcs = [])
      options = []

      if opts.instance_of?(Hash)
        opts.each do |k, v|
          k = k.to_s
          options << "#{k.start_with?("-") ? "" : (k.length > 1 ? "--" : "-")}#{k}#{v ? " " : ""}#{v}"
        end
      elsif opts.instance_of?(Array)
        options = opts
      else
        options << opts
      end

      try_cnt = 0

      begin
        syscmd("#{$CFG.get(:bin, ver == 4 ? :iptables : :ip6tables)} #{options.join(" ")}", valid_rcs)

      rescue VpsAdmind::CommandFailed => err
        if err.rc == 1 && err.output =~ /Resource temporarily unavailable/
          if try_cnt == 3
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
