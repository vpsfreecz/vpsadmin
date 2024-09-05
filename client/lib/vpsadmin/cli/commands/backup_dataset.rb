require 'time'

module VpsAdmin::CLI::Commands
  class BackupDataset < BaseDownload
    cmd :backup, :dataset
    args '[DATASET_ID] FILESYSTEM'
    desc 'Backup dataset locally'

    LocalSnapshot = Struct.new(:name, :hist_id, :creation) do
      def creation=(c)
        self[:creation] = c.to_i
      end
    end

    def options(opts)
      @opts = {
        rotate: true,
        min_snapshots: 30,
        max_snapshots: 45,
        max_age: 30,
        attempts: 10,
        checksum: true,
        delete_after: true,
        sudo: true
      }

      opts.on('-p', '--pretend', 'Print what would the program do') do
        @opts[:pretend] = true
      end

      opts.on('-r', '--[no-]rotate', 'Delete old snapshots (enabled)') do |r|
        @opts[:rotate] = r
      end

      opts.on('-m', '--min-snapshots N', Integer, 'Keep at least N snapshots (30)') do |m|
        exit_msg('--min-snapshots must be greater than zero') if m <= 0
        @opts[:min_snapshots] = m
      end

      opts.on('-M', '--max-snapshots N', Integer, 'Keep at most N snapshots (45)') do |m|
        exit_msg('--max-snapshots must be greater than zero') if m <= 0
        @opts[:max_snapshots] = m
      end

      opts.on('-a', '--max-age N', Integer, 'Delete snapshots older then N days (30)') do |m|
        exit_msg('--max-age must be greater than zero') if m <= 0
        @opts[:max_age] = m
      end

      opts.on('-x', '--max-rate N', Integer, 'Maximum download speed in kB/s') do |r|
        exit_msg('--max-rate must be greater than zero') if r <= 0
        @opts[:max_rate] = r
      end

      opts.on('-q', '--quiet', 'Print only errors') do |q|
        @opts[:quiet] = q
      end

      opts.on('-s', '--safe-download', 'Download to a temp file (needs 2x disk space)') do |s|
        @opts[:safe] = s
      end

      opts.on('--retry-attemps N', Integer, 'Retry N times to recover from download error (10)') do |n|
        exit_msg('--retry-attempts must be greater than zero') if n <= 0
        @opts[:attempts] = n
      end

      opts.on('-i', '--init-snapshots N', Integer, 'Download max N snapshots initially') do |s|
        exit_msg('--init-snapshots must be greater than zero') if s <= 0
        @opts[:init_snapshots] = s
      end

      opts.on('--[no-]checksum', 'Verify checksum of the downloaded data (enabled)') do |c|
        @opts[:checksum] = c
      end

      opts.on('-d', '--[no-]delete-after', 'Delete the file from the server after successful download (enabled)') do |d|
        @opts[:delete_after] = d
      end

      opts.on('--no-snapshots-as-error', 'Consider no snapshots to download as an error') do
        @opts[:no_snapshots_error] = true
      end

      opts.on('--[no-]sudo', 'Use sudo to run zfs if not run as root (enabled)') do |s|
        @opts[:sudo] = s
      end
    end

    def exec(args)
      if args.size == 1 && /^\d+$/ !~ args[0]
        fs = args[0]

        ds_id = read_dataset_id(fs)

        ds = if ds_id
               @api.dataset.show(ds_id)
             else
               dataset_chooser
             end

      elsif args.size != 2
        warn 'Provide DATASET_ID and FILESYSTEM arguments'
        exit(false)

      else
        ds = @api.dataset.show(args[0].to_i)
        fs = args[1]
      end

      check_dataset_id!(ds, fs)
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
        exit_msg(
          "Nothing to transfer: no snapshots with history id #{ds.current_history_id}",
          error: @opts[:no_snapshots_error]
        )
      end

      for_transfer = []

      latest_local_snapshot = local_state[ds.current_history_id] \
                              && local_state[ds.current_history_id].last
      found_latest = false

      # This is the first run within this history id, no local snapshots are
      # present
      if !latest_local_snapshot && @opts[:init_snapshots]
        remote_state[ds.current_history_id] =
          remote_state[ds.current_history_id].last(@opts[:init_snapshots])
      end

      remote_state[ds.current_history_id].each do |snap|
        found = false

        local_state.each_value do |local_snapshots|
          found = local_snapshots.detect { |s| s.name == snap.name }
          break if found
        end

        if !found_latest && latest_local_snapshot \
           && latest_local_snapshot.name == snap.name
          found_latest = true

        elsif latest_local_snapshot
          next unless found_latest
        end

        for_transfer << snap unless found
      end

      if for_transfer.empty?
        if found_latest
          exit_msg(
            'Nothing to transfer: all snapshots with history id ' \
            "#{ds.current_history_id} are already present locally",
            error: @opts[:no_snapshots_error]
          )

        else
          exit_msg(<<~END
            Unable to transfer: the common snapshot has not been found

            This can happen when the latest local snapshot was deleted from the server,
            i.e. you have not backed up this dataset for quite some time.

            You can either rename or destroy the whole current history id:

              zfs rename #{fs}/#{ds.current_history_id} #{fs}/#{ds.current_history_id}.old

            or

              zfs list -r -t all #{fs}/#{ds.current_history_id}
              zfs destroy -r #{fs}/#{ds.current_history_id}

            which will destroy all snapshots with this history id.

            You can also destroy the local backup completely or backup to another dataset
            and start anew.
          END
                  )
        end
      end

      unless @opts[:quiet]
        puts "Will download #{for_transfer.size} snapshots:"
        for_transfer.each { |s| puts "  @#{s.name}" }
        puts
      end

      if @opts[:pretend]
        pretend_state = local_state.clone
        pretend_state[ds.current_history_id] ||= []
        pretend_state[ds.current_history_id].concat(for_transfer.map do |s|
          LocalSnapshot.new(s.name, ds.current_history_id, Time.iso8601(s.created_at).to_i)
        end)

        rotate(fs, pretend: pretend_state) if @opts[:rotate]

      else
        # Find the common snapshot between server and localhost, so that the transfer
        # can be incremental.
        shared_name = local_state[ds.current_history_id] \
                      && !local_state[ds.current_history_id].empty? \
                      && local_state[ds.current_history_id].last.name
        shared = nil

        if shared_name
          shared = remote_state[ds.current_history_id].detect { |s| s.name == shared_name }

          for_transfer.insert(0, shared) if shared && !for_transfer.detect { |s| s.id == shared.id }
        end

        write_dataset_id!(ds, fs) unless written_dataset_id?
        transfer(local_state, for_transfer, ds.current_history_id, fs)
        rotate(fs) if @opts[:rotate]
      end
    end

    protected

    def transfer(local_state, snapshots, hist_id, fs)
      ds = "#{fs}/#{hist_id}"
      no_local_snapshots = local_state[hist_id].nil? || local_state[hist_id].empty?

      zfs(:create, nil, ds) if local_state[hist_id].nil?

      if no_local_snapshots
        msg "Performing a full receive of @#{snapshots.first.name} to #{ds}"

        if @opts[:safe]
          safe_download(ds, snapshots.first)

        else
          run_piped(zfs_cmd(:recv, '-F', ds)) do
            SnapshotSend.new({}, @api).do_exec({
                                                 snapshot: snapshots.first.id,
                                                 send_mail: false,
                                                 delete_after: @opts[:delete_after],
                                                 max_rate: @opts[:max_rate],
                                                 checksum: @opts[:checksum],
                                                 quiet: @opts[:quiet]
                                               })
          end || exit_msg('Receive failed')
        end
      end

      return unless !no_local_snapshots || snapshots.size > 1

      msg 'Performing an incremental receive of ' \
          "@#{snapshots.first.name} - @#{snapshots.last.name} to #{ds}"

      if @opts[:safe]
        safe_download(ds, snapshots.last, snapshots.first)

      else
        run_piped(zfs_cmd(:recv, '-F', ds)) do
          SnapshotSend.new({}, @api).do_exec({
                                               snapshot: snapshots.last.id,
                                               from_snapshot: snapshots.first.id,
                                               send_mail: false,
                                               delete_after: @opts[:delete_after],
                                               max_rate: @opts[:max_rate],
                                               checksum: @opts[:checksum],
                                               quiet: @opts[:quiet]
                                             })
        end || exit_msg('Receive failed')
      end
    end

    def safe_download(ds, snapshot, from_snapshot = nil)
      part, full = snapshot_tmp_file(snapshot, from_snapshot)

      unless File.exist?(full)
        attempts = 0

        begin
          SnapshotDownload.new({}, @api).do_exec({
                                                   snapshot: snapshot.id,
                                                   from_snapshot: from_snapshot && from_snapshot.id,
                                                   format: from_snapshot ? :incremental_stream : :stream,
                                                   file: part,
                                                   max_rate: @opts[:max_rate],
                                                   checksum: @opts[:checksum],
                                                   quiet: @opts[:quiet],
                                                   resume: true,
                                                   delete_after: @opts[:delete_after],
                                                   send_mail: false
                                                 })
        rescue Errno::ECONNREFUSED,
               Errno::ETIMEDOUT,
               Errno::EHOSTUNREACH,
               Errno::ECONNRESET => e
          warn "Connection error: #{e.message}"

          attempts += 1

          if attempts >= @opts[:attempts]
            warn 'Run out of attempts'
            exit(false)

          else
            warn 'Retry in 60 seconds'
            sleep(60)
            retry
          end
        end

        File.rename(part, full)
      end

      run_piped(zfs_cmd(:recv, '-F', ds)) do
        Process.exec("zcat #{full}")
      end || exit_msg('Receive failed')

      File.delete(full)
    end

    def rotate(fs, pretend: false)
      msg 'Rotating snapshots'
      local_state = pretend || parse_tree(fs)

      # Order snapshots by date of creation
      snapshots = local_state.values.flatten.sort do |a, b|
        a.creation <=> b.creation
      end

      cnt = local_state.values.inject(0) { |sum, local_snapshots| sum + local_snapshots.count }
      deleted = 0
      oldest = Time.now.to_i - (@opts[:max_age] * 60 * 60 * 24)

      snapshots.each do |s|
        ds = "#{fs}/#{s.hist_id}"

        if (cnt - deleted) <= @opts[:min_snapshots] \
            || (s.creation > oldest && (cnt - deleted) <= @opts[:max_snapshots])
          break
        end

        deleted += 1
        local_state[s.hist_id].delete(s)

        msg "Destroying #{ds}@#{s.name}"
        zfs(:destroy, nil, "#{ds}@#{s.name}", pretend: pretend)
      end

      local_state.each do |hist_id, local_snapshots|
        next unless local_snapshots.empty?

        ds = "#{fs}/#{hist_id}"

        msg "Destroying #{ds}"
        zfs(:destroy, nil, ds, pretend: pretend)
      end
    end

    def parse_tree(fs)
      ret = {}

      # This is intentionally done by two zfs commands, because -d2 would include
      # nested subdatasets, which should not be there, but the user might create
      # them and it could confuse the program.
      zfs(:list, '-r -d1 -tfilesystem -H -oname', fs).split("\n")[1..].each do |name|
        last_name = name.split('/').last
        ret[last_name.to_i] = [] if dataset?(last_name)
      end

      zfs(
        :get,
        '-Hrp -d2 -tsnapshot -oname,property,value name,creation',
        fs
      ).split("\n").each do |line|
        name, property, value = line.split
        ds, snap_name = name.split('@')
        ds_name = ds.split('/').last
        next unless dataset?(ds_name)

        hist_id = ds_name.to_i

        if (snap = ret[hist_id].detect { |s| s.name == snap_name })
          snap.send("#{property}=", value)

        else
          snap = LocalSnapshot.new(snap_name, hist_id)
          ret[hist_id] << snap
        end
      end

      ret
    end

    def dataset?(name)
      /^\d+$/ =~ name
    end

    def read_dataset_id(fs)
      ds_id = zfs(:get, '-H -ovalue cz.vpsfree.vpsadmin:dataset_id', fs).strip
      return nil if ds_id == '-'

      @dataset_id = ds_id.to_i
    end

    def check_dataset_id!(ds, fs)
      return unless @dataset_id && @dataset_id != ds.id

      warn "Dataset '#{fs}' is used to backup remote dataset with id '#{@dataset_id}', not '#{ds.id}'"
      exit(false)
    end

    def written_dataset_id?
      !@dataset_id.nil?
    end

    def write_dataset_id!(ds, fs)
      zfs(:set, "cz.vpsfree.vpsadmin:dataset_id=#{ds.id}", fs)
    end

    # Run two processes like +block | cmd2+, where block's stdout is piped into
    # cmd2's stdin.
    def run_piped(cmd2, &block)
      r, w = IO.pipe
      pids = []

      pids << Process.fork do
        r.close
        $stdout.reopen(w)
        block.call
      end

      pids << Process.fork do
        w.close
        $stdin.reopen(r)
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
      s += 'sudo ' if @opts[:sudo] && Process.euid != 0
      s += 'zfs'
      "#{s} #{cmd} #{opts} #{fs}"
    end

    def zfs(cmd, opts, fs, pretend: false)
      cmd = zfs_cmd(cmd, opts, fs)

      if pretend
        puts "> #{cmd}"
        return
      end

      ret = `#{cmd}`
      exit_msg("#{cmd} failed with exit code #{$?.exitstatus}") if $?.exitstatus != 0
      ret
    end

    def dataset_chooser(vps_only: false)
      user = @api.user.current
      vpses = @api.vps.list(user: user.id)

      vps_map = {}
      vpses.each do |vps|
        vps_map[vps.dataset_id] = vps
      end

      i = 1
      ds_map = {}

      @api.dataset.index(user: user.id).each do |ds|
        if (vps = vps_map[ds.id])
          puts "(#{i}) VPS ##{vps.id}"

        else
          next if vps_only

          puts "(#{i}) Dataset #{ds.name}"
        end

        ds_map[i] = ds
        i += 1
      end

      loop do
        $stdout.write('Pick a dataset to backup: ')
        $stdout.flush

        i = $stdin.readline.strip.to_i
        next if i <= 0 || ds_map[i].nil?

        return ds_map[i]
      end
    end

    def snapshot_tmp_file(s, from_s = nil)
      base = if from_s
               ".snapshot_#{from_s.id}-#{s.id}.inc.dat.gz"

             else
               ".snapshot_#{s.id}.dat.gz"
             end

      ["#{base}.part", base]
    end

    def exit_msg(str, error: true)
      if error
        warn str
        exit(1)

      else
        msg str
        exit(0)
      end
    end
  end
end
