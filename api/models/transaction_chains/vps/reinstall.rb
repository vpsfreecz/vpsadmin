module TransactionChains
  class Vps::Reinstall < ::TransactionChain
    label 'Reinstall'

    def link_chain(vps, template)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      running = vps.running?

      # Transfer all snapshots to backup
      @pool = vps.dataset_in_pool.pool
      backup_datasets(vps)

      # Send the stop nevertheless, vpsAdmin information about VPS
      # status may not be up-to-date.
      use_chain(Vps::Stop, args: vps)

      if vps.node.openvz?
        reinstall_openvz(vps, template)

      else
        reinstall_vpsadminos(vps, template)
      end

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key], reversible: :keep_going)
      end

      if running
        # Set reversible to :keep_going, because we cannot be certain that
        # the template is correct and the VPS will start.
        use_chain(Vps::Start, args: vps, reversible: :keep_going)
      end
    end

    def reinstall_openvz(vps, template)
      # Destroy underlying dataset with all its descendants,
      # but do not delete the top-level dataset from database.
      use_chain(DatasetInPool::Destroy, args: [vps.dataset_in_pool, {
        recursive: true,
        top: false,
      }])

      # Destroy VPS configs, mounts, root
      append(Transactions::Vps::Destroy, args: vps)

      # Create the dataset again
      append(Transactions::Storage::CreateDataset, args: [
        vps.dataset_in_pool,
        vps.dataset_in_pool.refquota ? {refquota: vps.dataset_in_pool.refquota} : nil
      ]) do
        # FIXME: would be nicer to put this into confirmation of DatasetInPool::Destroy
        increment(vps.dataset_in_pool.dataset, 'current_history_id')
      end

      # Create VPS
      vps.os_template = template

      append(Transactions::Vps::Create, args: vps) do
        edit(vps, os_template_id: template.id)

        # Reset features
        vps.vps_features.each do |f|
          edit(f, enabled: 0)
        end

        just_create(vps.log(:reinstall, {
          id: template.id,
          name: template.name,
          label: template.label,
        }))
      end

      append(Transactions::Vps::ApplyConfig, args: vps)
      use_chain(Vps::Mounts, args: vps)

      append(Transactions::Vps::Resources, args: [
        vps,
        vps.get_cluster_resources(%i(memory swap cpu))
      ])

      # OpenVZ VPS can in fact have only one interface, so all IPs can be
      # handled at once like this.
      vps.ip_addresses.all.each do |ip|
        append(
          Transactions::NetworkInterface::AddRoute,
          args: [ip.network_interface, ip, false],
        )
      end

      append(Transactions::Vps::DnsResolver, args: [
        vps,
        vps.dns_resolver,
        vps.dns_resolver
      ])
    end

    def reinstall_vpsadminos(vps, template)
      # Remove all local snapshots
      vps.dataset_in_pool.snapshot_in_pools.each do |sip|
        use_chain(SnapshotInPool::Destroy, args: sip)
      end

      # Reinstall CT
      append_t(Transactions::Vps::Reinstall, args: [vps, template]) do |t|
        t.edit(vps, os_template_id: template.id)
        t.increment(vps.dataset_in_pool.dataset, 'current_history_id')
      end
    end

    def backup_datasets(vps)
      datasets = []

      vps.dataset_in_pool.dataset.subtree.arrange.each do |k, v|
        datasets.concat(recursive_serialize(k, v))
      end

      # Transfer all datasets to all backups
      datasets.each do |dip|
        dip.dataset.dataset_in_pools.joins(:pool).where(
          'pools.role = ?', ::Pool.roles[:backup]
        ).each do |dst|
          use_chain(TransactionChains::Dataset::Transfer, args: [dip, dst])
        end
      end
    end

    def recursive_serialize(dataset, children)
      ret = []

      # First parents
      dip = dataset.dataset_in_pools.where(pool: @pool).take

      return ret unless dip

      lock(dip)

      ret << dip

      # Then children
      children.each do |k, v|
        if v.is_a?(::Dataset)
          dip = v.dataset_in_pools.where(pool: @pool).take
          next unless dip

          lock(dip)
          ret << dip

        else
          ret.concat(recursive_serialize(k, v))
        end
      end

      ret
    end
  end
end
