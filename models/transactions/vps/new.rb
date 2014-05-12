module Transactions::Vps
  class New < ::Transaction
    t_chain true

    def link_chain(dep, vps)
      Transaction.chain(dep) do
        append(Create, args: vps)
        append(ApplyConfig, args: vps)
      end
    end
  end
end
