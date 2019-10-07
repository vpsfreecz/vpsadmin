module NodeCtld
  class Commands::Export::AddHosts < Commands::Base
    handle 5405

    def exec
      s = NfsServer.new(@export_id, nil)

      @hosts.each do |host|
        if @snapshot_clone
          s.add_snapshot_export(
            @pool_fs,
            @snapshot_clone,
            @as,
            host['address'],
            host['options'],
          )
        else
          s.add_filesystem_export(
            @pool_fs,
            @dataset_name,
            @as,
            host['address'],
            host['options'],
          )
        end
      end

      ok
    end

    def rollback
      s = NfsServer.new(@export_id, nil)

      @hosts.each do |host|
        s.remove_export(@as, host['address'])
      end

      ok
    end
  end
end
