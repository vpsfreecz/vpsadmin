module NodeCtld
  class Worker
    attr_reader :cmd, :activity_token

    def initialize(cmd, activity: nil, activity_token: nil)
      @cmd = cmd
      @activity = activity
      @activity_token = activity_token
      @killing = false
      work
    end

    def work
      return nil if working?

      @thread = Thread.new do
        @cmd.execute
      end
    end

    def kill(set_status = true)
      @activity&.worker_killed(@activity_token)
      @killing = true

      @thread.kill
      @cmd.killed(set_status)

      sub = @cmd.subtask
      Process.kill('TERM', sub) if sub

      @killing = false
    end

    def working?
      (@thread && @thread.alive?) || @killing
    end
  end
end
