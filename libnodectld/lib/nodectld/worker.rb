require 'thread'

module NodeCtld
  class Worker
    attr_reader :cmd

    def initialize(cmd)
      @cmd = cmd
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
