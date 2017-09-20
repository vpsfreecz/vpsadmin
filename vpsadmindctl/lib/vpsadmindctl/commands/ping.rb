module VpsAdmindCtl::Commands
  class Ping < VpsAdmindCtl::Command
    description 'Check if vpsAdmind is alive'

    def process
      if @res[:pong] == 'pong'
        puts 'pong'

      else
        {:status => :failed, :error => 'vpsAdmind did not respond correctly'}
      end
    end
  end
end
