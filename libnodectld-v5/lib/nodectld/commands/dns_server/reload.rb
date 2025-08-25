module NodeCtld
  class Commands::DnsServer::Reload < Commands::Base
    handle 5510
    needs :system

    def exec
      if @zone
        syscmd("rndc reload #{@zone}")
      else
        syscmd('rndc reload')
      end
    end

    def rollback
      ok
    end
  end
end
