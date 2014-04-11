class CommandFailed < StandardError
  attr_reader :cmd, :rc, :output

  def initialize(cmd, rc, out)
    @cmd = cmd
    @rc = rc
    @output = out
  end

  def message
    "command '#{@cmd}' exited with code '#{@rc}', output: '#{@output}'"
  end
end

class CommandNotImplemented < StandardError

end

class Executor
  attr_accessor :output

  def initialize(veid = nil, params = {}, command = nil, daemon = nil)
    @veid = veid
    @params = params
    @output = {}
    @command = command
    @daemon = daemon
    @m_attr = Mutex.new
  end

  def attrs
    @m_attr.synchronize do
      yield
    end
  end

  def step
    attrs do
      @step
    end
  end

  def subtask
    attrs do
      @subtask
    end
  end

  def zfs?
    [:zfs, :zfs_compat].include?($CFG.get(:vpsadmin, :fstype))
  end

  # Sets appropriate command state, wait for lock, run block and unclock VPS again
  def acquire_lock(db = nil)
    if @lock_acquired
      yield
      return ok
    end

    db ||= Db.new
    set_step("[waiting for lock]")

    Backuper.wait_for_lock(db, @veid) do
      @lock_acquired = true

      begin
        yield
      rescue => error
        Backuper.unlock(db, @veid)
        @lock_acquired = false
        raise error
      end
    end

    @lock_acquired = false

    ok
  end

  def acquire_lock_unless(cond)
    if cond
      yield
    else
      acquire_lock do
        yield
      end
    end

    ok
  end

  # Pretend that we have a lock
  def assume_lock
    @lock_acquired = true

    yield

    @lock_acquired = false

    ok
  end

  def try_harder(attempts = 3)
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

  def vzctl(cmd, veid, opts = {}, save = false, valid_rcs = [])
    options = []

    if opts.instance_of?(Hash)
      opts.each do |k, v|
        k = k.to_s
        v.each do |s|
          options << "#{k.start_with?("-") ? "" : "--"}#{k} #{s}"
        end
      end
    else
      options << opts
    end

    syscmd("#{$CFG.get(:vz, :vzctl)} #{cmd} #{veid} #{options.join(" ")} #{"--save" if save}", valid_rcs)
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
    set_step(cmd)

    out = ""
    log "Exec #{cmd}"

    IO.popen("exec #{cmd} 2>&1") do |io|
      attrs do
        @subtask = io.pid
      end

      out = io.read
    end

    attrs do
      @subtask = nil
    end

    if $?.exitstatus != 0 and not valid_rcs.include?($?.exitstatus)
      raise CommandFailed.new(cmd, $?.exitstatus, out)
    end

    {:ret => :ok, :output => out, :exitstatus => $?.exitstatus}
  end

  def post_save(con)

  end

  def ok
    {:ret => :ok}
  end

  private

  def set_step(str)
    attrs do
      @step = str
    end
  end
end
