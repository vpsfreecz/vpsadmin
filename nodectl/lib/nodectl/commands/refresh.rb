module NodeCtl::Commands
  class Refresh < NodeCtl::Command
    description 'Update VPS status, traffic counters, storage usage and server status'

    def process
      puts 'Refreshed'
    end
  end
end
