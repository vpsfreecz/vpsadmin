module Transactions::Vps
  class ReinstallChain < ::Transaction
    # t_chain true

    def link_chain(dep, vps)
      Transaction.chain(dep) do
        append(Reinstall, args: vps)
        append(ApplyConfig, args: vps)
        append(Mounts, args: [vps, false])
      end
    end
  end
end
