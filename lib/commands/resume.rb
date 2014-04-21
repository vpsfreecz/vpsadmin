module Commands
  class Resume < Command
    description 'Resume execution of queued transactions'

    def process
      puts 'Resumed'
    end
  end
end
