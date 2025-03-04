module TransactionChains
  class Vps::Autostart < ::TransactionChain
    label 'Autostart'

    def link_chain(vps, enable:, priority: nil)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      new_priority = priority || vps.autostart_priority

      append_t(
        Transactions::Vps::Autostart,
        args: [vps],
        kwargs: { enable:, priority: }
      ) do |t|
        t.just_create(vps.log(:autostart, {
                                enable:,
                                priority: new_priority
                             }))
        t.edit(vps, autostart_enable: enable, autostart_priority: new_priority)
      end
    end
  end
end
