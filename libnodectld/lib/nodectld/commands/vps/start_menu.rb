module NodeCtld
  class Commands::Vps::StartMenu < Commands::Base
    handle 2030
    needs :system, :osctl

    def exec
      if @new_timeout > 0
        set_start_menu(@new_timeout)
      else
        unset_start_menu
      end
    end

    def rollback
      if @original_timeout > 0
        set_start_menu(@original_timeout)
      else
        unset_start_menu
      end
    end

    protected
    def set_start_menu(timeout)
      osctl(%i(ct set start-menu), @vps_id, {timeout: timeout})
    end

    def unset_start_menu
      osctl(%i(ct unset start-menu), @vps_id)
    end
  end
end
