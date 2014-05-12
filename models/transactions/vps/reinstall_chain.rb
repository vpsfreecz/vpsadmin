module Transactions::Vps
  class ReinstallChain < ::Transaction
    t_chain true

    def link_chain(dep, vps)
      Transaction.chain(dep) do
        append(Reinstall, args: vps)
        append(ApplyConfig, args: vps)
        # TODO
        # - mounts
        # - DNS resolver
      end
    end
  end
end
