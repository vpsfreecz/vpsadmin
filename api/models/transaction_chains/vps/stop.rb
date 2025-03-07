module TransactionChains
  class Vps::Stop < ::TransactionChain
    label 'Stop'

    def link_chain(vps, start_timeout: 'infinity', rollback_stop: nil, kill: false)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(
        Transactions::Vps::Stop,
        args: [vps],
        kwargs: {
          start_timeout:,
          rollback_stop: rollback_stop.nil? ? included? : rollback_stop,
          kill:
        }
      ) do |t|
        t.just_create(vps.log(:stop)) unless included?
        t.edit(vps, autostart_enable: false)
      end
    end
  end
end
