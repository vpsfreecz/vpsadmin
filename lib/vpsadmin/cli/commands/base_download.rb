module VpsAdmin::CLI::Commands
  class BaseDownload < HaveAPI::CLI::Command
    protected
    def find_or_create_dl(opts)
      @api.snapshot_download.index(snapshot: opts[:snapshot]).each do |r|
        return [r, false] if opts[:from_snapshot] == (r.from_snapshot && r.from_snapshot_id)
      end

      [@api.snapshot_download.create(opts), true]
    end
  end
end
