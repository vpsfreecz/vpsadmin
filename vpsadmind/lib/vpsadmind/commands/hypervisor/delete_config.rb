module VpsAdmind
  class Commands::Hypervisor::DeleteConfig < Commands::Base
    handle 7302
    needs :hypervisor
    
    def exec
      File.delete(sample_conf_path(@name))

      ok
    end

    def rollback
      call_cmd(Commands::Hypervisor::CreateConfig, {
          :name => @name,
          :vps_config => @vps_config
      })
    end
  end
end
