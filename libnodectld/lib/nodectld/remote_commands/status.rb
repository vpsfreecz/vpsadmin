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
            open: queue.open?,
            start_delay: queue.start_delay,
            started: queue.started?,
            workers: {},
            reservations: queue.reservations
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
              progress: p
            }
          end

          res_queues[name] = q
        end
      end

      consoles = @daemon.console.stats

      subtasks = nil
      @daemon.chain_blockers do |blockers|
        subtasks = blockers || {}
      end

      q_size = db.prepared(
        'SELECT COUNT(t.id) AS cnt
        FROM transactions t
        INNER JOIN transaction_chains c ON t.transaction_chain_id = c.id
        WHERE t.node_id = ? AND t.done = 0 AND c.state IN (1, 3)',
        $CFG.get(:vpsadmin, :node_id)
      ).get['cnt']

      {
        ret: :ok,
        output: {
          state: {
            initialized: @daemon.initialized?,
            run: @daemon.run?,
            pause: @daemon.paused?,
            status: @daemon.exitstatus
          },
          queues: res_queues,
          export_console: $CFG.get(:console, :enable),
          consoles: consoles,
          subprocesses: subtasks,
          start_time: @daemon.start_time.to_i,
          queue_size: q_size - queue_size
        }
      }
    end
  end
end
