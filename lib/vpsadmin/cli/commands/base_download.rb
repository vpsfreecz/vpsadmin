module VpsAdmin::CLI::Commands
  class BaseDownload < HaveAPI::CLI::Command
    protected
    def find_or_create_dl(opts, do_create = true)
      @api.snapshot_download.index(snapshot: opts[:snapshot]).each do |r|
        return [r, false] if opts[:from_snapshot] == (r.from_snapshot && r.from_snapshot_id)
      end

      if do_create
        [@api.snapshot_download.create(opts), true]

      else
        [nil, true]
      end
    end

    def msg(str)
      puts str unless @opts[:quiet]
    end

    def warn_msg(str)
      warn str unless @opts[:quiet]
    end
  end
end
