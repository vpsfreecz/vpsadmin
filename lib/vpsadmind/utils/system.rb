module VpsAdmind
  module Utils::System
    def try_harder(attempts = 3)
      @output ||= {}
      @output[:attempts] = []

      attempts.times do |i|
        begin
          return yield
        rescue CommandFailed => err
          log "Attempt #{i+1} of #{attempts} failed for '#{err.cmd}'"
          @output[:attempts] << {
              :cmd => err.cmd,
              :exitstatus => err.rc,
              :error => err.output,
          }

          raise err if i == attempts - 1

          sleep(5)
        end
      end
    end

    def scp(what, where, opts = nil)
      syscmd("#{$CFG.get(:bin, :scp)} #{opts} #{what} #{where}")
    end

    def rsync(cfg, vars, rcs = [23, 24])
      cmd = $CFG.get(*cfg)
      vars[:rsync] ||= $CFG.get(:bin, :rsync)

      vars.each do |k, v|
        cmd = cmd.gsub(/%\{#{k}\}/, v)
      end

      try_harder do
        syscmd(cmd, rcs)
      end
    end

    def syscmd(cmd, valid_rcs = [])
      current_cmd = Thread.current[:command]
      current_cmd.step = cmd if current_cmd

      out = ""
      log "Exec #{cmd}"

      IO.popen("exec #{cmd} 2>&1") do |io|
        current_cmd.subtask = io.pid if current_cmd

        out = io.read
      end

      current_cmd.subtask = nil if current_cmd

      if $?.exitstatus != 0 and not valid_rcs.include?($?.exitstatus)
        raise CommandFailed.new(cmd, $?.exitstatus, out)
      end

      {:ret => :ok, :output => out, :exitstatus => $?.exitstatus}
    end
  end
end
