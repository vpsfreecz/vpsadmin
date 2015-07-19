module TransactionChains
  class IntegrityCheck::Cluster < ::TransactionChain
    label 'Cluster'

    def link_chain(modules)
      check = ::IntegrityCheck.create!(
          user: ::User.current
      )

      concerns(:affect, [check.class.name, check.id])

      ::Node.all.each do |n|
        use_chain(IntegrityCheck::Node, args: [check, n, modules])
      end

      append(Transactions::IntegrityCheck::Finalize, args: check)

      check
    end
  end
end
