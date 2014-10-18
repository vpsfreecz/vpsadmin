module VpsAdmind::RemoteCommands
  class Status < Base
    handle :status

    def exec
      db = VpsAdmind::Db.new
      res_workers = {}

      @daemon.workers do |workers|
        workers.each do |wid, w|
          h = w.cmd.handler

          res_workers[wid] = {
              :id => w.cmd.id,
              :type => w.cmd.trans['t_type'].to_i,
              :handler => "#{h.split('::')[-2..-1].join('::')}",
              :step => w.cmd.step,
              :pid => w.cmd.subtask,
              :start => w.cmd.time_start,
          }
        end
      end

      consoles = {}
      VpsAdmind::VzConsole.consoles do |c|
        c.each do |veid, console|
          consoles[veid] = console.usage
        end
      end

      st = db.prepared_st('SELECT COUNT(t_id) AS cnt FROM transactions WHERE t_server = ? AND t_done = 0', $CFG.get(:vpsadmin, :server_id))
      q_size = st.fetch()[0]
      st.close

      {:ret => :ok,
       :output => {
           :state => {
               :run => @daemon.run?,
               :pause => @daemon.paused?,
               :status => @daemon.exitstatus,
           },
           :workers => res_workers,
           :threads => $CFG.get(:vpsadmin, :threads),
           :export_console => @daemon.export_console,
           :consoles => consoles,
           :start_time => @daemon.start_time.to_i,
           :queue_size => q_size - res_workers.size,
       }
      }
    end
  end
end
