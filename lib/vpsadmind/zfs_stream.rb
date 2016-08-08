module VpsAdmind
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
    def send_to(addr, port: nil)
      pipe_cmd("nc #{addr} #{port}")
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
      monitor_progress(err)
      err.close

      Process.wait(zfs_pid)
      Process.wait(cmd_pid)
    end
    
    def pipe_io(io)
      @pipeline = []
      zfs_pid, err = zfs_send(io)

      @cmd.step = @pipeline.join(' | ') if @cmd
      monitor_progress(err)
      err.close

      Process.wait(zfs_pid)
    end

    def zfs_send(stdout)
      r_err, w_err = IO.pipe 
        
      if @from_snapshot
        cmd = "zfs send -v -I @#{@from_snapshot} #{path}@#{@snapshot}"

      else
        cmd = "zfs send -v #{path}@#{@snapshot}"
      end

      @pipeline << cmd

      pid = Process.fork do
        r_err.close
        STDOUT.reopen(stdout)
        STDERR.reopen(w_err)

        Process.exec(cmd)
      end

      w_err.close

      # Skip the first three lines, i.e.:
      #   send from @ to <ds> estimated size is 19.8G
      #   total estimated size is 19.8G
      #   TIME        SENT   SNAPSHOT
      @size = parse_total_size(r_err.readline)
      2.times { r_err.readline }

      [pid, r_err]
    end

    def monitor_progress(io)
      transfered = 0

      io.each_line do |line|
        n = parse_transfered(line)
        change = transfered == 0 ? n : n - transfered
        transfered = n

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
        cmd = zfs(:send, "-nv -I @#{@from_snapshot}", "#{path}@#{@snapshot}")

      else
        cmd = zfs(:send, '-nv', "#{path}@#{@snapshot}")
      end
      
      rx = /^total estimated size is ([^$]+)$/
      m = rx.match(cmd[:output])

      raise ArgumentError, 'unable to estimate size' if m.nil?
      
      parse_size(m[1])
    end

    # @param str [String] output of zfs send -v
    def parse_total_size(str)
      rx = /estimated size is ([^$]+)$/
      m = rx.match(str)

      raise ArgumentError, 'unable to estimate size' if m.nil?
      
      parse_size(m[1])
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
        units = %w(K M G T)

        if i = units.index(suffix)
          (i+1).times { size *= 1024 }

        else
          fail "unsupported suffix '#{suffix}'"
        end
      end

      (size / 1024 / 1024).round
    end
  end
end
