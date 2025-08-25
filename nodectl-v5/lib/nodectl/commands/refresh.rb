module NodeCtl
  class Commands::Refresh < Command::Remote
    cmd :refresh
    description 'Update VPS status, traffic counters, storage usage and server status'

    def process
      puts 'Refreshed'
    end
  end
end
