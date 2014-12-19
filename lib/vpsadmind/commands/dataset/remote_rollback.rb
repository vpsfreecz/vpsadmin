module VpsAdmind
  class Commands::Dataset::RemoteRollback < Commands::Base
    handle 5210

    include Utils::System

    def exec
      recv = "zfs recv -F #{primary_ds}"
      send = "zfs send #{@backup_pool_fs}/#{@dataset_name}/#{@tree}/#{@branch}@#{@snapshot}"

      syscmd("#{send} | ssh #{@primary_node_addr} #{recv}")
    end

    def rollback
      zfs(:destroy, nil, primary_ds)
    end

    protected
    def primary_ds
      "#{@primary_pool_fs}/#{@dataset_name}.rollback"
    end
  end
end
