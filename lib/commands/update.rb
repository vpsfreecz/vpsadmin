module Commands
  class Stop < Command
    description 'Safely stop vpsAdmind, then update by git pull and start again'

    def process
      puts 'Update scheduled'
    end
  end
end
