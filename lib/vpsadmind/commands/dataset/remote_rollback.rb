module VpsAdmind
  class Commands::Dataset::RemoteRollback < Commands::Base
    handle 5210

    include Utils::System

    def exec
      recv = "zfs recv -F #{@primary_pool_fs}/#{@dataset_name}.rollback"
      send = "zfs send #{@backup_pool_fs}/#{@dataset_name}/#{@branch}@#{@snapshot}"

      syscmd("#{send} | ssh #{@primary_node_addr} #{recv}")
    end
  end
end
