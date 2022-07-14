module NodeCtld
  class Commands::VpsBgp::RestartPeer < Commands::Base
    handle 5506
    needs :system, :vps_bgp

    def exec
      syscmd("birdc restart #{peer_name}")
    end

    def rollback
      ok
    end
  end
end
