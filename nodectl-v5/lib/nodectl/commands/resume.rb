module NodeCtl
  class Commands::Resume < Command::Remote
    cmd :resume
    description 'Resume execution of queued transactions'

    def process
      puts 'Resumed'
    end
  end
end
