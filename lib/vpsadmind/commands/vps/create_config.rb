module VpsAdmind
  class Commands::Vps::CreateConfig < Commands::Base
    handle 4003

    needs :system, :vz, :vps

    def exec
      # Create a new empty config
      File.open(ve_conf, 'w').close

      # Set VE root, private and OS template
      vzctl(:set, @vps_id, {
          :root => ve_root,
          :private => ve_private,
          :ostemplate => @os_template
      }, true)
    end

    def rollback
      File.delete(ve_conf) if File.exists?(ve_conf)
      ok
    end
  end
end
