module NodeCtld::RemoteCommands
  class Status < Base
    handle :status

    def exec
      db = NodeCtld::Db.new
      res_queues = {}
      queue_size = nil

      @daemon.queues do |queues|
        queue_size = queues.worker_count

        queues.each do |name, queue|
          q = {
            threads: queue.size,
            urgent: queue.urgent_size,
            start_delay: queue.start_delay,
            started: queue.started?,
            workers: {},
            reservations: queue.reservations,
          }

          queue.each do |wid, w|
            h = w.cmd.handler

            start = w.cmd.time_start
            p = w.cmd.progress
            p[:time] = p[:time].to_i if p

            q[:workers][wid] = {
              id: w.cmd.id,
              type: w.cmd.trans['handle'].to_i,
              handler: "#{h.split('::')[-2..-1].join('::')}",
              step: w.cmd.step,
              pid: w.cmd.subtask,
              start: start && start.localtime.to_i,
              progress: p,
            }
          end

          res_queues[name] = q
        end
      end

      consoles = {}
      NodeCtld::Console::Wrapper.consoles do |c|
        c.each do |veid, console|
          consoles[veid] = console.usage
        end
      end

      subtasks = nil
      @daemon.chain_blockers do |blockers|
        subtasks = blockers || {}
      end

      mounts = nil
      @daemon.delayed_mounter.mounts do |m|
        mounts = m.dup
      end

      q_size = db.prepared(
        'SELECT COUNT(id) AS cnt FROM transactions WHERE node_id = ? AND done = 0',
        $CFG.get(:vpsadmin, :node_id)
      ).get['cnt']

      {
        ret: :ok,
        output: {
          state: {
            run: @daemon.run?,
            pause: @daemon.paused?,
            status: @daemon.exitstatus,
          },
          queues: res_queues,
          export_console: @daemon.export_console,
          consoles: consoles,
          subprocesses: subtasks,
          delayed_mounts: mounts,
          start_time: @daemon.start_time.to_i,
          queue_size: q_size - queue_size,
        }
      }
    end
  end
end
