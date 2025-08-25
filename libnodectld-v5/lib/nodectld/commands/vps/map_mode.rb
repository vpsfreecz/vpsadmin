module NodeCtld
  class Commands::Vps::MapMode < Commands::Base
    handle 2034
    needs :system, :osctl, :vps

    def exec
      set_map_mode(@new_map_mode)
    end

    def rollback
      set_map_mode(@original_map_mode)
    end

    protected

    def set_map_mode(mode)
      honor_state do
        osctl(%i[ct stop], @vps_id)
        osctl(%i[ct set map-mode], [@vps_id, mode])
      end
    end
  end
end
