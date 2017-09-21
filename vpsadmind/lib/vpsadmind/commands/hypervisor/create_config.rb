module VpsAdmind
  class Commands::Hypervisor::CreateConfig < Commands::Base
    handle 7301
    needs :hypervisor

    def exec
      f = File.new(sample_conf_path(@name), 'w')
      f.write(@vps_config)
      f.close

      ok
    end

    def rollback
      File.delete(sample_conf_path(@name)) if File.exists?(sample_conf_path(@name))
      ok
    end
  end
end
