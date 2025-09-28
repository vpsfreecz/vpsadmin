module NodeCtld
  class Commands::NetworkInterface::HostIpDel < Commands::Base
    handle 2023

    def exec
      NetworkInterface.new(@pool_fs, @vps_id, @interface).del_host_addr(@addr, @prefix)
      ok
    end

    def rollback
      NetworkInterface.new(@pool_fs, @vps_id, @interface).add_host_addr(@addr, @prefix)
      ok
    end
  end
end
