module Transactions::Vps
  class New < ::Transaction
    t_chain true

    def link_chain(dep, vps)
      Transaction.chain(dep) do
        append(Create, vps)
        append(ApplyConfig, vps)
      end
    end
  end
end
