module TransactionChains
  class Lifetimes::Wrapper < ::TransactionChain
    label 'State change'

    def link_chain(obj, target, states, enter, chains, log)
      concerns(:affect, [obj.class.name, obj.id])

      log.save!
      dir = enter ? :enter : :leave

      states.each do |s|
        last = s == states.last
        default = true

        if chains[s] && chains[s][dir]
          puts "\nCALLING chain #{chains[s][dir]}\n"
          default = use_chain(chains[s][dir], args: [
              obj,
              s == last,
              last,
              log
          ])
        end

        if last
          if empty?
            obj.update!(
                object_state: target,
                expiration_date: log.expiration_date
            )

          else
            append(Transactions::Utils::NoOp, args: ::Node.first_available.id) do
              if default.nil? || default != false
                edit(
                    obj,
                    object_state: ::VpsAdmin::API::Lifetimes::STATES.index(target),
                    expiration_date: log.expiration_date
                )
              end

              just_create(log)
            end
          end
        end
      end

      fail 'fancy rollback'
    end
  end
end
