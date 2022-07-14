module NodeCtld
  class Commands::VpsBgp::CreatePeer < Commands::Base
    handle 5501
    needs :system, :pool, :vps_bgp

    def exec
      generate_peer_config
      ok
    end

    def rollback
      remove_peer_config
      ok
    end
  end
end
