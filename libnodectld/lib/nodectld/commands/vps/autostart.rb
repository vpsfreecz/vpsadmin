module NodeCtld
  class Commands::Vps::Autostart < Commands::Base
    handle 2028
    needs :system, :osctl

    def exec
      set_autostart(@enable)
    end

    def rollback
      if @revert
        set_autostart(!@enable)
      else
        ok
      end
    end

    protected
    def set_autostart(enable)
      if enable
        osctl(%i(ct set autostart), @vps_id)
      else
        osctl(%i(ct unset autostart), @vps_id)
      end
    end
  end
end
