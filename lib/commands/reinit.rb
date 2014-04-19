module Commands
  class Reinit < Command
    description 'Reinitialize firewall chains and rules'

    def process
      puts 'Reinitialized'
      @res.each do |k, v|
        puts "#{v} rules for IPv#{k}"
      end
    end
  end
end
