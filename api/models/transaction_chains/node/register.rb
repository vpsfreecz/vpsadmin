module TransactionChains
  class Node::Register < ::TransactionChain
    label 'Register'

    def link_chain(node, opts)
      node.save!

      lock(node)
      concerns(:affect, [node.class.name, node.id])
      reserved_ports = reservation_port_range

      if opts[:maintenance]
        m = ::MaintenanceLock.lock_for(node)

        raise 'unable to lock the node' unless m.lock!(node)
      end

      # Port reservations
      append(Transactions::Utils::NoOp, args: node.id) do
        if %w[node storage].include?(node.role)
          reserved_ports.each do |port|
            r = ::PortReservation.create!(
              node:,
              port:
            )

            just_create(r)
          end
        end

        just_create(node)
      end
    end

    protected

    def reservation_port_range
      10_000...20_000
    end
  end
end
