module NodeCtld
  class Commands::Vps::Chown < Commands::Base
    handle 3041
    needs :system, :osctl, :vps

    def exec
      chown_to(@new_userns_map)
      ok
    end

    def rollback
      chown_to(@original_userns_map)
      ok
    end

    protected
    def chown_to(userns_map)
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(%i(ct chown), [@vps_id, userns_map])
      end
    end
  end
end
