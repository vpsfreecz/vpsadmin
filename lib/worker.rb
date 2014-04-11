class Worker
  attr_reader :cmd

  def initialize(cmd)
    @cmd = cmd
    work
  end

  def work
    if self.working?
      return nil
    end

    @thread = Thread.new do
      @cmd.execute
    end
  end

  def kill(set_status = true)
    @thread.stop
    @cmd.killed(set_status)
    @thread.kill!

    sub = @cmd.subtask
    Process.kill("TERM", sub) if sub
  end

  def working?
    @thread and @thread.alive?
  end
end
