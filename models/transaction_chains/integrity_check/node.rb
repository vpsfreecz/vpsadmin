module TransactionChains
  class IntegrityCheck::Node < ::TransactionChain
    label 'Node'

    def link_chain(check, node, modules)
      check ||= ::IntegrityCheck.create!(
          user: ::User.current
      )
      concerns(:affect, [check.class.name, check.id])

      modules.each do |m|
        case m
          when :storage
            append(Transactions::IntegrityCheck::Storage, args: [check, node])

          when :vps
            if node.server_type == 'node'
              append(Transactions::IntegrityCheck::Vps, args: [check, node])
            end

          else
            fail "unsupported module #{m}"
        end
      end
      
      append(Transactions::IntegrityCheck::Finalize, args: check) unless included?

      check
    end
  end
end
