module NodeCtld::RemoteCommands
  class CtHook < Base
    handle :ct_hook

    def exec
      case @hook_name.to_sym
      when :veth_up
        NodeCtld::VethMap.set(@vps_id, @ct_veth, @host_veth)
        NodeCtld::NetAccounting.netif_up(@vps_id.to_i, @ct_veth)
      end

      ok
    end
  end
end
