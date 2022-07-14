module NodeCtld
  class Commands::VpsBgp::DestroyPeer < Commands::Base
    handle 5504
    needs :system, :pool, :vps_bgp

    def exec
      backup_peer_config
      remove_peer_config
      ok
    end

    def rollback
      restore_peer_config
      ok
    end
  end
end
