module NodeCtld
  class Commands::VpsBgp::UpdatePeer < Commands::Base
    handle 5502
    needs :system, :pool, :vps_bgp

    def exec
      backup_peer_config
      generate_peer_config
      ok
    end

    def rollback
      restore_peer_config
      ok
    end
  end
end
