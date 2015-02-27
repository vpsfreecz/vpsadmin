module VpsAdmind
  class Commands::Vps::CreateConfig < Commands::Base
    handle 4003

    needs :system, :vz, :vps

    def exec
      File.open(ve_conf, 'w').close
      vzctl(:set, @vps_id, {:root => ve_root, :private => ve_private}, true)
    end

    def rollback
      File.delete(ve_conf) if File.exists?(ve_conf)
      ok
    end
  end
end
