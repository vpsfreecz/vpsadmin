module TransactionChains
  class IntegrityCheck::Cluster < ::TransactionChain
    label 'Cluster'

    def link_chain(opts, modules)
      check = ::IntegrityCheck.create!(
          user: ::User.current
      )

      concerns(:affect, [check.class.name, check.id])

      q = ::Node.all

      if opts[:skip_maintenance]
        q = q.where(maintenance_lock: ::MaintenanceLock.maintain_lock(:no))
      end

      q.each do |n|
        use_chain(IntegrityCheck::Node, args: [check, n, modules])
      end

      append(Transactions::IntegrityCheck::Finalize, args: check)

      check
    end
  end
end
