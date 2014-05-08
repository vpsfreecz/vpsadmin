module Transactions::Vps
  class ReinstallChain < ::Transaction
    t_chain true

    def link_chain(dep, vps)
      Transaction.chain(dep) do
        append(Reinstall, vps)
        append(ApplyConfig, vps)
        # TODO
        # - mounts
        # - DNS resolver
      end
    end
  end
end
