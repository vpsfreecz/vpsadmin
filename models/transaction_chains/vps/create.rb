module TransactionChains
  class Vps::Create < ::TransactionChain
    label 'Create VPS'

    def link_chain(vps, add_ips)
      lock(vps)

      pool = vps.node.pools.where(role: :hypervisor).take!

      ds = ::Dataset.create(
          name: vps.id.to_s,
          user: vps.user,
          user_editable: false,
          user_create: true
      )

      vps.dataset_in_pool = DatasetInPool.create(
          dataset: ds,
          pool: pool
      )

      lock(vps.dataset_in_pool)

      append(Transactions::Storage::CreateDataset, args: vps.dataset_in_pool) do
        create(ds)
        create(vps.dataset_in_pool)
      end

      append(Transactions::Vps::Create, args: vps) do
        create(vps)
      end

      use_chain(Vps::ApplyConfig, vps, VpsConfig.default_config_chain(vps.node.location))

      if add_ips
        ips = []
        versions = [4]
        versions << 6 if vps.node.location.has_ipv6

        versions.each do |v|
          begin
            ::IpAddress.transaction do
              ip = ::IpAddress.pick_addr!(vps.node.location, v)
              lock(ip)

              ips << ip
            end

          rescue ActiveRecord::RecordNotFound
            next # FIXME: notify admins, report some kind of an error?
          end
        end

        use_chain(Vps::AddIp, vps, ips)
      end

      if vps.vps_onboot
        use_chain(TransactionChains::Vps::Start, vps)
      end

      vps.save!

      # mapping, last_id = StorageExport.create_default_exports(self, depend: last_id)
      # create_default_mounts(mapping)
      #
      # Transactions::Vps::Mounts.fire_chained(last_id, self, false)
    end
  end
end
