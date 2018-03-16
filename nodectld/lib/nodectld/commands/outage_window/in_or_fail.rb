module NodeCtld
  class Commands::OutageWindow::InOrFail < Commands::Base
    handle 2102
    needs :outage_window

    def exec
      fail 'not in a window' unless windows.open?
      ok
    end

    def rollback
      ok
    end
  end
end
