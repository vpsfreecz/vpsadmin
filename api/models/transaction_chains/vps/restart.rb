module TransactionChains
  class Vps::Restart < ::TransactionChain
    label 'Restart'

    def link_chain(vps, start_timeout: 'infinity', kill: false)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(
        Transactions::Vps::Restart,
        args: [vps],
        kwargs: { start_timeout:, kill: }
      ) do |t|
        t.just_create(vps.log(:restart, force: kill)) unless included?
        t.edit(vps, autostart_enable: true)
      end
    end
  end
end
