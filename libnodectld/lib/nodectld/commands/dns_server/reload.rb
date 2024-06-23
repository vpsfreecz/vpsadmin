module NodeCtld
  class Commands::DnsServer::Reload < Commands::Base
    handle 5510
    needs :system

    def exec
      syscmd('rndc reload')
      ok
    end

    def rollback
      ok
    end
  end
end
