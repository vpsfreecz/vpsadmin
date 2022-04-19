module VpsAdmind
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system, :vz, :vps, :zfs

    def exec
      # FIXME: what about onboot param?

      create_opts = {
          :ostemplate => @template,
          :private => ve_private,
      }

      create_opts[:hostname] = @hostname if @hostname

      vzctl(:create, @vps_id, create_opts)
      vzctl(:set, @vps_id, {
          :applyconfig => 'basic'
      }, true)
    end

    def rollback
      call_cmd(Commands::Vps::Destroy, {:vps_id => @vps_id})
      # Note: the private/ itself is not deleted. Dataset destroyal
      # should follow this transaction.
      ok
    end
  end
end
