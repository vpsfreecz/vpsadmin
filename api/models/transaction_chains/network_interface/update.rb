module TransactionChains
  class NetworkInterface::Update < ::TransactionChain
    label 'Update'

    def link_chain(netif, attrs)
      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      orig_netif = ::NetworkInterface.find(netif.id)

      netif.assign_attributes(attrs)
      raise ActiveRecord::RecordInvalid, netif unless netif.valid?

      shaper = {}

      netif.changed.each do |attr|
        case attr
        when 'name'
          append_t(Transactions::NetworkInterface::Rename, args: [
            netif,
            netif.name_was,
            netif.name,
          ]) do |t|
            t.edit(netif, name: netif.name)

            t.just_create(netif.vps.log(:netif_rename, {
              id: netif.id,
              name: netif.name_was,
              new_name: netif.name,
            })) unless included?
          end

        when 'max_tx', 'max_rx'
          shaper[attr.to_sym] = netif.send(attr)
        end
      end

      if shaper.any?
        append_t(
          Transactions::NetworkInterface::SetShaper,
          args: [orig_netif],
          kwargs: shaper,
        ) do |t|
          t.edit(netif, **shaper)
        end
      end

      netif
    end
  end
end
