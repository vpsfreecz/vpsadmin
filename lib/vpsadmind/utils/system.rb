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

    def scp(what, where, opts = nil, valid_rcs=[])
      syscmd("#{$CFG.get(:bin, :scp)} #{opts} #{what} #{where}", valid_rcs)
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
      log(:work, current_cmd || @command, cmd)

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

    def pipeline_r(*cmds)
      current_cmd = Thread.current[:command]
      current_cmd.step = cmds.to_s if current_cmd
      log(:work, current_cmd || @command, cmds.to_s)

      if RUBY_VERSION >= '1.9'
        last_stdout, threads = Open3.pipeline_r(*cmds)
        out = last_stdout.read
        last_stdout.close
        ret = nil

        threads.each do |t|
          ret = t.value.exitstatus
          raise CommandFailed.new(cmds.to_s, ret, out) if ret != 0
        end

        {:ret => :ok, :output => out, :exitstatus => ret}

      else
        # Ruby < 1.9 does not have Open3.pipeline_r, so it has to
        # be implemented here...
        children = []

        # First process - no stdin, save stdout
        stdout_r, stdout_w = IO.pipe

        child = Process.fork do
          puts cmds.first

          stdout_r.close

          STDOUT.reopen(stdout_w)
          STDERR.reopen(stdout_w)
          Process.exec(cmds.first)
        end

        stdout_w.close

        children << child

        # Middle processes - previous stdout to stdin
        cmds[1..-2].each do |cmd|
          p_r, p_w = IO.pipe

          child = Process.fork do
            p_r.close

            STDIN.reopen(stdout_r)
            STDOUT.reopen(p_w)
            STDERR.reopen(p_w)
            Process.exec(cmd)
          end

          p_w.close

          children << child

          stdout_r.close
          stdout_r = p_r
        end

        # Last process - previous stdout to stdin, return stdout
        last_stdout, p_w = IO.pipe

        child = Process.fork do
          last_stdout.close

          STDIN.reopen(stdout_r)
          STDOUT.reopen(p_w)
          STDERR.reopen(p_w)
          Process.exec(cmds.last)
        end

        stdout_r.close
        p_w.close

        children << child

        out = last_stdout.read
        last_status = nil

        children.each do |pid|
          _, last_status = Process.wait2(pid)

          raise CommandFailed.new(cmds.to_s, last_status, out) if last_status != 0
        end

        {:ret => :ok, :output => out, :exitstatus => last_status}
      end
    end
  end
end
