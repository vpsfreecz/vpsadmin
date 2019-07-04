require 'libosctl'

module NodeCtld
  class ZfsStream < OsCtl::Lib::Zfs::Stream
    def initialize(fs, snapshot, from_snapshot = nil)
      super(
        build_path(fs),
        snapshot,
        from_snapshot,
        compressed: true,
        properties: false,
      )
    end

    def send_recv(fs)
      super(build_path(fs))
    end

    def command(cmd)
      @cmd = cmd

      block = Proc.new do |total, transfered, changed|
        cmd.progress = {
          total: size,
          current: total,
          unit: :mib,
          time: Time.now,
        }
      end

      progress(&block)

      yield

      @cmd = nil
      @progress.delete(block)
    end

    protected
    def build_path(fs)
      path = [fs[:pool], fs[:dataset]]
      path << fs[:tree] << fs[:branch] if fs[:branch]

      File.join(*path)
    end

    def notify_exec(pipeline)
      return unless @cmd
      @cmd.step = pipeline.join(' | ')
    end
  end
end
