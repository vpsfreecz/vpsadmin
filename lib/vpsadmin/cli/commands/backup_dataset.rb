module VpsAdmin::CLI::Commands
  class BackupDataset < BaseDownload
    cmd :backup, :dataset
    args '[DATASET_ID] FILESYSTEM'
    desc 'Backup dataset locally'

    def options(opts)

    end

    def exec(args)
      if args.size != 2
      end

      if args.size == 1 && /^\d+$/ !~ args[0]
        ds = dataset_chooser
        fs = args[0]

      elsif args.size != 2
        warn "Provide DATASET_ID and FILESYSTEM arguments"
        exit(false)

      else
        ds = @api.dataset.show(args[0].to_i)
        fs = args[1]
      end

      snapshots = ds.snapshot.list

      local_state = parse_tree(fs)

      # - Find out current history ID
      # - If there are snapshots with this ID that are not present locally,
      #   download them
      #   - If the dataset for this history ID does not exist, create it
      #   - If it exists, check what snapshots are there and make an incremental
      #     download

      remote_state = {}

      snapshots.each do |s|
        remote_state[s.history_id] ||= []
        remote_state[s.history_id] << s
      end

      if remote_state[ds.current_history_id].nil? \
         || remote_state[ds.current_history_id].empty?
        puts "Nothing to transfer: no snapshots with history id #{ds.current_history_id}"
        exit
      end

      for_transfer = []

      remote_state[ds.current_history_id].each do |snap|
        found = false

        local_state.values.each do |snapshots|
          found = snapshots.index(snap.name)
          break if found
        end

        for_transfer << snap unless found
      end

      if for_transfer.empty?
        puts "Nothing to transfer: all snapshots with history id "+
             "#{ds.current_history_id} are already present locally"
        exit
      end

      puts "Will download #{for_transfer.size} snapshots:"
      for_transfer.each { |s| puts "  @#{s.name}" }
      puts
     
      # Find the common snapshot between server and localhost, so that the transfer
      # can be incremental.
      shared_name = local_state[ds.current_history_id] && local_state[ds.current_history_id].last
      shared = nil

      if shared_name
        shared = remote_state[ds.current_history_id].detect { |s| s.name == shared_name }

        if shared && !for_transfer.detect { |s| s.id == shared.id }
          for_transfer.insert(0, shared)
        end
      end

      transfer(local_state, for_transfer, ds.current_history_id, fs)
    end

    protected
    def transfer(local_state, snapshots, hist_id, fs)
      ds = "#{fs}/#{hist_id}"
      no_local_snapshots = local_state[hist_id].nil? || local_state[hist_id].empty?

      if local_state[hist_id].nil?
        zfs(:create, nil, ds)
      end
      
      if no_local_snapshots
        puts "Performing a full receive of @#{snapshots.first.name} to #{ds}"
        run_piped(zfs_cmd(:recv, '-F', ds)) do
          SnapshotSend.new({}, @api).do_exec({
              snapshot: snapshots.first.id,
              send_mail: false,
              delete_after: true,
          })
        end || exit_msg('Receive failed')
      end

      if !no_local_snapshots || snapshots.size > 1
        puts "Performing an incremental receive of "+
             "@#{snapshots.first.name} - @#{snapshots.last.name} to #{ds}"
        run_piped(zfs_cmd(:recv, '-F', ds)) do
          SnapshotSend.new({}, @api).do_exec({
              snapshot: snapshots.last.id,
              from_snapshot: snapshots.first.id,
              send_mail: false,
              delete_after: true,
          })
        end || exit_msg('Receive failed')
      end
    end

    def parse_tree(fs)
      ret = {}

      # This is intentionally done by two zfs commands, because -d2 would include
      # nested subdatasets, which should not be there, but the user might create
      # them and it could confuse the program.
      zfs(:list, '-r -d1 -tfilesystem -H -oname', fs).split("\n")[1..-1].each do |name|
        last_name = name.split('/').last
        ret[last_name.to_i] = [] if dataset?(last_name)
      end
      
      zfs(:list, '-r -d2 -tsnapshot -H -oname', fs).split("\n").each do |line|
        ds, snap = line.split('@')
        name = ds.split('/').last
        ret[name.to_i] << snap if dataset?(name)
      end

      ret
    end

    def dataset?(name)
      /^\d+$/ =~ name
    end

    # Run two processes like +block | cmd2+, where block's stdout is piped into
    # cmd2's stdin.
    def run_piped(cmd2, &block)
      r, w = IO.pipe
      pids = []

      pids << Process.fork do
        r.close
        STDOUT.reopen(w)
        block.call
      end

      pids << Process.fork do
        w.close
        STDIN.reopen(r)
        Process.exec(cmd2)
      end

      r.close
      w.close

      ret = true

      pids.each do |pid|
        Process.wait(pid)
        ret = false if $?.exitstatus != 0
      end

      ret
    end

    def zfs_cmd(cmd, opts, fs)
      s = ''
      s += 'sudo ' if Process.euid != 0
      s += 'zfs'
      "#{s} #{cmd} #{opts} #{fs}"
    end

    def zfs(*args)
      `#{zfs_cmd(*args)}`
    end

    def dataset_chooser
      user = @api.user.current
      vpses = @api.vps.list(user: user.id)

      vps_map = {}
      vpses.each do |vps|
        vps_map[vps.dataset_id] = vps
      end

      i = 1
      ds_map = {}

      @api.dataset.index(user: user.id).each do |ds|
        ds_map[i] = ds

        if vps = vps_map[ds.id]
          puts "(#{i}) VPS ##{vps.id}"

        else
          puts "(#{i}) Dataset #{ds.name}"
        end

        i += 1
      end

      loop do
        STDOUT.write('Pick a dataset to backup: ')
        STDOUT.flush

        i = STDIN.readline.strip.to_i
        next if i <= 0 || ds_map[i].nil?

        return ds_map[i]
      end
    end

    def exit_msg(msg)
      warn msg
      exit(1)
    end
  end
end
