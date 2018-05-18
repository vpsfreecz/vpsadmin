module NodeCtld
  class Commands::Vps::SetMap < Commands::Base
    handle 2021
    needs :system, :osctl, :vps, :zfs

    def exec
      set_map(@new)
      ok
    end

    def rollback
      set_map(@original)
      ok
    end

    protected
    def set_map(map)
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(%i(ct chown), [@vps_id, map['userns_map']])
      end
    end
  end
end
