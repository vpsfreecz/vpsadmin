module NodeCtld
  class Commands::Vps::Autostart < Commands::Base
    handle 2028
    needs :system, :osctl

    def exec
      set_autostart(@new)
    end

    def rollback
      if @revert
        set_autostart(@original)
      else
        ok
      end
    end

    protected

    def set_autostart(opts)
      if opts['enable']
        osctl(%i[ct set autostart], @vps_id, { priority: opts['priority'] })
      else
        osctl(%i[ct unset autostart], @vps_id)
      end
    end
  end
end
