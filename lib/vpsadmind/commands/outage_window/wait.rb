module VpsAdmind
  class Commands::OutageWindow::Wait < Commands::Base
    handle 2101
    needs :outage_window

    def exec
      # Are we in a window?
      return ok if windows.open?

      # Wait for next available window to open
      w = windows.closest
      w.wait

      ok
    end

    def rollback
      ok
    end
  end
end
