module NodeCtld::RemoteCommands
  class Status < Base
    handle :status

    def exec
      db = NodeCtld::Db.new

      workers = NodeCtld::Worker.list.map do |cmd|
        start = cmd.time_start
        p = cmd.progress
        p[:time] = p[:time].to_i if p

        {
          transaction_id: cmd.transaction_id,
          command_id: cmd.command_id,
          handle: cmd.handle,
          handler: "#{cmd.handler.to_s.split('::')[-2..-1].join('::')}",
          method: cmd.method,
          step: cmd.step,
          pid: cmd.subtask,
          start: start && start.localtime.to_i,
          progress: p,
        }
      end

      consoles = {}
      NodeCtld::Console::Wrapper.consoles do |c|
        c.each do |veid, console|
          consoles[veid] = console.usage
        end
      end

      subtasks = NodeCtld::TransactionBlocker.list

      mounts = nil
      @daemon.delayed_mounter.mounts do |m|
        mounts = m.dup
      end

      {
        ret: :ok,
        output: {
          state: {
            run: @daemon.run?,
            pause: NodeCtld::Worker.paused?,
            status: @daemon.exitstatus,
          },
          workers: workers,
          export_console: @daemon.export_console,
          consoles: consoles,
          subprocesses: subtasks,
          delayed_mounts: mounts,
          start_time: @daemon.start_time.to_i,
        }
      }
    end
  end
end
