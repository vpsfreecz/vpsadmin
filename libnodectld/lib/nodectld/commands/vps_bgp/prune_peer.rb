module NodeCtld
  class Commands::VpsBgp::PrunePeer < Commands::Base
    handle 5505
    needs :system, :pool, :vps_bgp

    def exec
      prune_peer_backups
      ok
    end
  end
end
