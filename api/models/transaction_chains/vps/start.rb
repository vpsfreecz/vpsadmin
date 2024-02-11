module TransactionChains
  class Vps::Start < ::TransactionChain
    label 'Start'

    def link_chain(vps, start_timeout: 'infinity')
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(
        Transactions::Vps::Start,
        args: [vps],
        kwargs: { start_timeout: start_timeout, rollback_start: included? }
      ) do |t|
        t.just_create(vps.log(:start)) unless included?
        t.edit(vps, autostart_enable: true)
      end
    end
  end
end
