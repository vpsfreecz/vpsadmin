module TransactionChains
  class NetworkInterface::Update < ::TransactionChain
    label 'Netif*'
    allow_empty

    def link_chain(netif, attrs)
      lock(netif)
      lock(netif.vps)
      concerns(:affect, [netif.vps.class.name, netif.vps.id])

      orig_netif = ::NetworkInterface.find(netif.id)

      netif.assign_attributes(attrs)
      raise ActiveRecord::RecordInvalid, netif unless netif.valid?

      return netif unless netif.changed?

      # Handle rename first, so that other transactions can use `netif.name`,
      # which contains the new name.
      if netif.changed.include?('name')
        append_t(Transactions::NetworkInterface::Rename, args: [
                   netif,
                   netif.name_was,
                   netif.name
                 ]) do |t|
          t.edit(netif, name: netif.name)

          unless included?
            t.just_create(netif.vps.log(:netif_rename, {
                                          id: netif.id,
                                          name: netif.name_was,
                                          new_name: netif.name
                                        }))
          end
        end
      end

      shaper = { name: netif.name }

      netif.changed.each do |attr|
        case attr
        when 'max_tx', 'max_rx'
          shaper[attr.to_sym] = netif.send(attr)

        when 'enable'
          t_class =
            if netif.enable
              Transactions::NetworkInterface::Enable
            else
              Transactions::NetworkInterface::Disable
            end

          append_t(t_class, args: [netif]) do |t|
            t.edit(netif, enable: netif.enable)

            t.just_create(netif.vps.log(:netif_enable, {
                                          id: netif.id,
                                          name: netif.name,
                                          enable: netif.enable
                                        }))
          end
        end
      end

      if shaper.size > 1
        append_t(
          Transactions::NetworkInterface::SetShaper,
          args: [orig_netif],
          kwargs: shaper
        ) do |t|
          t.edit(netif, **shaper)
        end
      end

      netif
    end
  end
end
