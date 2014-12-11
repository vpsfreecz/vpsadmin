module VpsAdmind
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system, :vz, :vps, :zfs

    def exec
      # FIXME: what about onboot param?

      vzctl(:create, @vps_id, {
          :ostemplate => @template,
          :hostname => @hostname,
          :private => ve_private,
      })
      vzctl(:set, @vps_id, {
          :applyconfig => 'basic',
          :nameserver => @nameserver
      }, true)
    end
  end
end
