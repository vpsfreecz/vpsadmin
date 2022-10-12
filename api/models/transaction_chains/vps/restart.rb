module TransactionChains
  class Vps::Restart < ::TransactionChain
    label 'Restart'

    def link_chain(vps, start_timeout: 180)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(
        Transactions::Vps::Restart,
        args: [vps],
        kwargs: {start_timeout: start_timeout},
      ) do |t|
        t.just_create(vps.log(:restart)) unless included?
        t.edit(vps, autostart_enable: true)
      end
    end
  end
end
