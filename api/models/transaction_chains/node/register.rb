module TransactionChains
  class Node::Register < ::TransactionChain
    label 'Register'

    def link_chain(node, opts)
      node.save!

      lock(node)
      concerns(:affect, [node.class.name, node.id])

      if opts[:maintenance]
        m = ::MaintenanceLock.lock_for(node)

        fail 'unable to lock the node' unless m.lock!(node)
      end

      # Port reservations
      append(Transactions::Utils::NoOp, args: node.id) do
        if %w(node storage).include?(node.role)
          10000.times do |i|
            r = ::PortReservation.create!(
              node: node,
              port: 10000 + i
            )

            just_create(r)
          end
        end

        just_create(node)
      end
    end
  end
end
