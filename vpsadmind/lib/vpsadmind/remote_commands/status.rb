module VpsAdmind::RemoteCommands
  class Status < Base
    handle :status

    def exec
      db = VpsAdmind::Db.new

      workers = VpsAdmind::Worker.list.map do |cmd|
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
      VpsAdmind::Console::Wrapper.consoles do |c|
        c.each do |veid, console|
          consoles[veid] = console.usage
        end
      end

      subtasks = VpsAdmind::TransactionBlocker.list

      mounts = nil
      @daemon.delayed_mounter.mounts do |m|
        mounts = m.dup
      end

      st = db.prepared_st(
          'SELECT COUNT(id) AS cnt FROM transactions WHERE node_id = ? AND done = 0',
          $CFG.get(:vpsadmin, :server_id)
      )
      q_size = st.fetch()[0]
      st.close

      {
        ret: :ok,
        output: {
          state: {
            run: @daemon.run?,
            pause: VpsAdmind::Worker.paused?,
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
