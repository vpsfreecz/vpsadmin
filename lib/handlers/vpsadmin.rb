require 'lib/executor'
require 'lib/daemon'

class VpsAdmin < Executor
  def reload
    Process.kill("HUP", Process.pid)
    ok
  end

  def stop
    VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_STOP)
    if @params[:force]
      walk_workers { |w| :silent }
      drop_workers
    end
    ok
  end

  def restart
    VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_RESTART)
    if @params[:force]
      walk_workers { |w| :silent }
      drop_workers
    end
    ok
  end

  def update
    VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_UPDATE)
    if @params[:force]
      walk_workers { |w| :silent }
      drop_workers
    end
    ok
  end

  def status
    db = Db.new
    res_workers = {}

    @daemon.workers do |workers|
      workers.each do |wid, w|
        h = w.cmd.handler

        res_workers[wid] = {
            :id => w.cmd.id,
            :type => w.cmd.trans["t_type"].to_i,
            :handler => "#{h[:class]}.#{h[:method]}",
            :step => w.cmd.step,
            :pid => w.cmd.subtask,
            :start => w.cmd.time_start,
        }
      end
    end

    consoles = {}
    VzConsole.consoles do |c|
      c.each do |veid, console|
        consoles[veid] = console.usage
      end
    end

    st = db.prepared_st("SELECT COUNT(t_id) AS cnt FROM transactions WHERE t_server = ? AND t_done = 0", $CFG.get(:vpsadmin, :server_id))
    q_size = st.fetch()[0]
    st.close

    {:ret => :ok,
     :output => {
         :workers => res_workers,
         :threads => $CFG.get(:vpsadmin, :threads),
         :export_console => @daemon.export_console,
         :consoles => consoles,
         :start_time => @daemon.start_time.to_i,
         :queue_size => q_size - res_workers.size,
     }
    }
  end

  def kill
    cnt = 0
    msgs = {}

    if @params[:transactions] == "all"
      cnt = walk_workers { |w| true }
    elsif @params[:types]
      @params[:types].each do |t|
        killed = walk_workers { |w| w.cmd.type == t }

        if killed == 0
          msgs[t] = "No transaction with this type"
        end

        cnt += killed
      end
    else
      @params[:transactions].each do |t|
        killed = walk_workers { |w| w.cmd.id == t }

        if killed == 0
          msgs[t] = "No such transaction"
        end

        cnt += killed
      end
    end

    {:ret => :ok, :output => {:killed => cnt, :msgs => msgs}}
  end

  def reinit
    log "Reinitialization requested"
    r = nil

    Firewall.mutex.synchronize do
      fw = Firewall.new
      r = fw.reinit
    end

    ok.update({:output => r})
  end

  def refresh
    log "Update requested"

    @daemon.update_all
    ok
  end

  def install
    db = Db.new

    node_id = $CFG.get(:vpsadmin, :server_id)

    if @params[:create]
      if @params[:id]
        node_id = @params[:id]
      elsif node_id > 1
        # it's ok
      else
        node_id = nil
      end

      loc = @params[:location].to_i

      if loc == 0
        st = db.prepared_st("SELECT location_id FROM locations WHERE location_label = ?", @params[:location])
        row = st.fetch()

        if row.nil?
          raise CommandFailed.new(nil, nil, "Location '#{@params[:location]}' does not exist")
        end

        loc = row[0].to_i
      end

      name = get_hostname

      db.prepared("INSERT INTO servers SET
			            server_id = ?, server_name = ?, server_type = ?, server_location = ?,
			            server_ip4 = ?
			            ON DUPLICATE KEY UPDATE
			            server_name = ?, server_type = ?, server_location = ?,
			            server_ip4 = ?
			            ",
                  # insert
                  node_id, name, @params[:role], loc, @params[:addr],
                  # update
                  name, @params[:role], loc, @params[:addr]
      )
      node_id = db.insert_id

      if @params[:role] == "node"
        db.prepared("INSERT INTO node_node SET
				            node_id = ?, max_vps = ?, ve_private = ?, fstype = ?
				            ON DUPLICATE KEY UPDATE
				            max_vps = ?, ve_private = ?, fstype = ?
				            ",
                    # insert
                    node_id, @params[:maxvps], @params[:ve_private], @params[:fstype],
                    # update
                    @params[:maxvps], @params[:ve_private], @params[:fstype]
        )
      end

      log "Node registered in database:"
      log "\tid = #{node_id}"
      log "\tname = #{name}"
      log "\trole = #{@params[:role]}"
      log "\tlocation = #{loc}"
      log "\taddr = #{@params[:addr]}"

      case @params[:role]
        when "node"
          log "\tmaxvps = #{@params[:maxvps]}"
          log "\tve_private = #{@params[:ve_private]}"
          log "\tfstype = #{@params[:fstype]}"
      end

      refresh
    end

    log "Updating public keys"

    get_pubkeys.each do |t, k|
      db.prepared("INSERT INTO node_pubkey (node_id, `type`, `key`) VALUES (?, ?, ?)
			             ON DUPLICATE KEY UPDATE `key` = ?",
                  node_id, t, k, k)
    end

    if @params[:propagate]
      Transaction.new(db).cluster_wide({
                                           :m_id => 0,
                                           :node => node_id,
                                           :type => :gen_known_hosts,
                                       })
    end

    if @params[:gen_configs]
      log "Creating configs"
      n = Node.new
      db.query("SELECT name, config FROM config").each_hash do |cfg|
        log "  #{cfg["name"]}"
        n.create_config(cfg)
      end
    end

    if @params[:ssh_key]
      priv = syscfg_get(db, "node_private_key")
      pub = nil
      type = "dsa"
      priv_path = nil
      pub_path = nil

      if priv.nil?
        log "No SSH key configured, generating new one"
        priv_path = "/root/.ssh/id_#{type}"
        pub_path = "#{priv_path}.pub"

        File.delete(priv_path) if File.exists?(priv_path)

        syscmd("#{$CFG.get(:bin, :ssh_keygen)} -q -t #{type} -N \"\" -f #{priv_path}")

        priv = File.new(priv_path).read
        pub = File.new(pub_path).read

        syscfg_set(db, "node_private_key", priv)
        syscfg_set(db, "node_public_key", pub)
        syscfg_set(db, "node_key_type", type)

      else
        log "SSH key configured"

        type = syscfg_get(db, "node_key_type")
        priv_path = "/root/.ssh/id_#{type}"
        pub_path = "#{priv_path}.pub"

        priv = syscfg_get(db, "node_private_key")
        pub = syscfg_get(db, "node_public_key")
      end

      open(priv_path, "w") do |f|
        f.puts priv
        f.chmod(0600)
      end

      open(pub_path, "w") do |f|
        f.puts pub
      end

      open("/root/.ssh/authorized_keys", "a") do |f|
        f.puts pub
      end

      log "SSH keys written"
    end

    ok.update({:output => {:node_id => node_id}})
  end

  def get
    case @params[:resource]
      when 'config'
        ok.update({:output => {:config => $CFG.get}})

      when 'queue'
        queue = []

        @daemon.workers do |workers|
          db = Db.new

          @daemon.select_commands(db, @params[:limit]).each_hash do |row|
            t_id = row['t_id'].to_i

            catch (:next) do
              workers.each do |wid, w|
                throw :next if w.cmd.id.to_i == t_id
              end

              queue << {
                  :id => t_id,
                  :type => row['t_type'].to_i,
                  :time => row['t_time'].to_i,
                  :m_id => row['t_m_id'].to_i,
                  :vps_id => row['t_vps'].to_i,
                  :depends_on => row['t_depends_on'].to_i,
                  :fallback => row['t_fallback'],
                  :urgent => row['t_urgent'].to_i == 1,
                  :priority => row['t_priority'].to_i,
                  :params => row['t_param'],
              }
            end
          end

          db.close

        end

        ok.update({:output => {:queue => queue}})

      else
        raise CommandFailed.new(nil, nil, "Unknown resource #{@params[:resource]}")
    end
  end

  def set
    case @params[:resource]
      when 'config'
        @params[:config].each do |change|
          $CFG.patch(change)
        end

        ok

      else
        raise CommandFailed.new(nil, nil, "Unknown resource #{@params[:resource]}")
    end
  end

  def walk_workers
    killed = 0

    @daemon.workers do |workers|
      workers.each do |wid, w|
        ret = yield(w)
        if ret
          log "Killing transaction #{w.cmd.id}"
          w.kill(ret != :silent)
          killed += 1
        end
      end
    end

    killed
  end

  def drop_workers
    @daemon.workers { |w| w.clear }
  end

  def get_hostname
    if @params[:name]
      @params[:name]
    else
      syscmd($CFG.get(:bin, :hostname))[:output].strip
    end
  end

  def get_pubkeys
    ret = {}

    $CFG.get(:node, :pubkey, :types).each do |t|
      ret[t] = File.open($CFG.get(:node, :pubkey, :path).gsub(/%\{type\}/, t)).read.strip
    end

    ret
  end

  def syscfg_get(db, key)
    st = db.prepared_st("SELECT cfg_value FROM sysconfig WHERE cfg_name = ?", key)
    ret = st.num_rows > 0 ? JSON.parse("{\"tmp\": #{st.fetch[0]} }")["tmp"] : nil
    st.close

    ret
  end

  def syscfg_set(db, key, val)
    encoded = val.to_json

    db.prepared("INSERT INTO sysconfig SET cfg_name = ?, cfg_value = ?
		             ON DUPLICATE KEY UPDATE cfg_value = ?",
                key, encoded, encoded)
  end
end
