module VpsAdmindCtl::Commands
  class Refresh < VpsAdmindCtl::Command
    description 'Update VPS status, traffic counters, storage usage and server status'

    def process
      puts 'Refreshed'
    end
  end
end
