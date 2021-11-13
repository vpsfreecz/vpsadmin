module VpsAdmind
  # Control class for ZFS send invocation.
  #
  # ZfsStream uses the `-v` flag of zfs send to monitor how the transfer progresses.
  # The following output from zfs send is parsed:
  #
  #   send from <snap1> to <snap2> estimated size is <n><unit>
  #   send from <snap2> to <snap3> estimated size is <n><unit>
  #   send from <snap3> to <snap4> estimated size is <n><unit>
  #   ...
  #   total estimated size is <n><unit>  # this is the size that is read
  #   TIME        SENT         SNAPSHOT
  #   HH:MM:SS    <n1><unit>   <snap>
  #   HH:MM:SS    <n2><unit>   <snap>
  #   HH:MM:SS    <n3><unit>   <snap>
  #   TIME        SENT         SNAPSHOT
  #   HH:MM:SS    <m1><unit>   <snap>
  #   HH:MM:SS    <m2><unit>   <snap>
  #   HH:MM:SS    <m3><unit>   <snap>
  #   ...
  #
  # A line with column headers separates transfers of snapshots listed at the top.
  # There might not be any transfered data between column headers if the snapshot
  # has zero (or possibly very little) size. Time and snapshot columns are ignored,
  # sent data are expected to increment and reset when the next snapshot is being
  # transfered.
  class ZfsStream
    include Utils::System
    include Utils::Zfs
    include Utils::Log

    # @params fs [Hash] filesystem
    # @option fs [String] pool
    # @option fs [String] tree
    # @option fs [String] branch
    # @option fs [String] dataset
    # @param snapshot [String]
    # @param from_snapshot [String]
    def initialize(fs, snapshot, from_snapshot = nil)
      @fs = fs
      @snapshot = snapshot
      @from_snapshot = from_snapshot
      @progress = []
    end

    # Write stream to `io`
    # @param io [IO] writable stream
    def write_to(io)
      zfs_send(io)
    end

    # Send stream over a socket.
    def send_to(addr, port: nil, timeout: 900)
      socat = "socat -u -T #{timeout} 'EXEC:\"#{full_zfs_send_cmd}\"' TCP:#{addr}:#{port}"

      @cmd.step = socat if @cmd
      log(:work, @cmd, socat)

      IO.popen("exec #{socat} 2>&1") do |io|
        @size = parse_total_size(io)
        monitor_progress(io)
      end
    end

    # Send stream to a local filesystem.
    def send_recv(fs)
      pipe_cmd("zfs recv -F #{build_path(fs)}")
    end

    # Get approximate stream size.
    # @return [Integer] size in MiB
    def size
      @size ||= approximate_size
    end

    # @yieldparam total [Integer] total number of transfered data
    # @yieldparam sent [Integer] transfered data since the last call
    def progress(&block)
      @progress << block
    end

    # @return [String] path
    def path
      @path ||= build_path(@fs)
    end

    def command(cmd)
      @cmd = cmd
      yield
      @cmd = nil
    end

    protected
    def pipe_cmd(cmd)
      @pipeline = []
      r, w = IO.pipe

      cmd_pid = Process.fork do
        STDIN.reopen(r)
        w.close
        Process.exec(cmd)
      end

      r.close

      zfs_pid, err = zfs_send(w)
      @pipeline << cmd

      w.close

      @cmd.step = @pipeline.join(' | ') if @cmd
      log(:work, @cmd, @pipeline.join(' | '))
      monitor_progress(err)
      err.close

      Process.wait(zfs_pid)
      Process.wait(cmd_pid)
    end

    def pipe_io(io)
      @pipeline = []
      zfs_pid, err = zfs_send(io)

      @cmd.step = @pipeline.join(' | ') if @cmd
      log(:work, @cmd, @pipeline.join(' | '))
      monitor_progress(err)
      err.close

      Process.wait(zfs_pid)
    end

    def zfs_send(stdout)
      r_err, w_err = IO.pipe
      cmd = full_zfs_send_cmd

      @pipeline << cmd

      pid = Process.fork do
        r_err.close
        STDOUT.reopen(stdout)
        STDERR.reopen(w_err)

        Process.exec(cmd)
      end

      w_err.close

      @size = parse_total_size(r_err)

      [pid, r_err]
    end

    def monitor_progress(io)
      total = 0
      transfered = 0

      io.each_line do |line|
        n = parse_transfered(line)

        if n
          change = transfered == 0 ? n : n - transfered
          transfered = n
          total += change

        else  # Transfer of another snapshot has begun, zfs send is counting from 0
          transfered = 0
          next
        end

        if @cmd
          @cmd.progress = {
              total: size,
              current: total,
              unit: :mib,
              time: Time.now
          }
        end

        @progress.each do |block|
          block.call(transfered, change)
        end
      end
    end

    def build_path(fs)
      path = [fs[:pool], fs[:dataset]]
      path << fs[:tree] << fs[:branch] if fs[:branch]

      File.join(*path)
    end

    def update_transfered(str)
      size = update_transfered(str)
    end

    def approximate_size
      if @from_snapshot
        cmd = zfs(:send, "-ncv -I @#{@from_snapshot}", "#{path}@#{@snapshot}")

      else
        cmd = zfs(:send, '-ncv', "#{path}@#{@snapshot}")
      end

      rx = /^total estimated size is ([^$]+)$/
      m = rx.match(cmd[:output])

      raise ArgumentError, 'unable to estimate size' if m.nil?

      parse_size(m[1])
    end

    # Reads from fd until total transfer size can be estimated.
    # @param fd [IO] IO object to read
    def parse_total_size(fd)
      rx = /total estimated size is ([^$]+)$/

      until fd.eof? do
        line = fd.readline

        m = rx.match(line)
        next if m.nil?

        return parse_size(m[1])
      end

      raise RuntimeError, 'unable to estimate total transfer size'
    end

    def parse_transfered(str)
      cols = str.split
      return if /^\d{2}:\d{2}:\d{2}$/ !~ cols[0].strip

      parse_size(cols[1])
    end

    def parse_size(str)
      size = str.to_f
      suffix = str.strip[-1]

      if suffix !~ /^\d+$/
        units = %w(B K M G T)

        if i = units.index(suffix)
          i.times { size *= 1024 }

        else
          fail "unsupported suffix '#{suffix}'"
        end
      end

      (size / 1024 / 1024).round
    end

    def full_zfs_send_cmd
      if @from_snapshot
        "zfs send -v -L -I @#{@from_snapshot} #{path}@#{@snapshot}"
      else
        "zfs send -v -L #{path}@#{@snapshot}"
      end
    end
  end
end
