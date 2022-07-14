module NodeCtld
  class Commands::VpsBgp::CommitPeer < Commands::Base
    handle 5503
    needs :system

    def exec
      if @direction == 'execute'
        syscmd('bird -d -p -c /etc/bird2.conf')
        syscmd('birdc configure')
      end

      ok
    end

    def rollback
      if @direction == 'rollback'
        syscmd('bird -d -p -c /etc/bird2.conf')
        syscmd('birdc configure')
      end

      ok
    end
  end
end
