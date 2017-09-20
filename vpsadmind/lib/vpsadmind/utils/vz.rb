module VpsAdmind
  module Utils::Vz
    def vzctl(cmd, veid, opts = {}, save = false, valid_rcs = [], cmd_opts = {})
      options = []

      if opts.instance_of?(Hash)
        opts.each do |k, v|
          k = k.to_s
          array_or_string_each(v) do |s|
            options << "#{k.start_with?('-') ? '' : '--'}#{k} #{s.nil? ? '""' : s}"
          end
        end
      else
        options << opts
      end

      cmd_opts[:valid_rcs] ||= valid_rcs

      syscmd2(
          "#{$CFG.get(:vz, :vzctl)} #{cmd} #{veid} #{options.join(" ")} #{"--save" if save}",
          cmd_opts
      )
    end

    def array_or_string_each(obj)
      if obj.is_a?(Array)
        if obj.empty?
          yield nil

        else
          obj.each { |v| yield v }
        end
      else
        yield obj
      end
    end
  end
end
