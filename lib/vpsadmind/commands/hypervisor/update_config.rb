module VpsAdmind
  class Commands::Hypervisor::UpdateConfig < Commands::Base
    handle 7303
    needs :hypervisor
    
    def exec
      create(@new)

      if @new['name'] != @original['name']
        File.delete(sample_conf_path(@original['name']))
      end

      ok
    end

    def rollback
      if @new['name'] == @original['name']
        create(@original)

      else
        p = sample_conf_path(@new['name'])
        File.delete(p) if File.exists?(p)
        create(@original)
      end

      ok
    end

    protected
    def create(cfg)
      f = File.new(sample_conf_path(cfg['name']), 'w')
      f.write(cfg['vps_config'])
      f.close
    end
  end
end
