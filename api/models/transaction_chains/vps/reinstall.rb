module TransactionChains
  class Vps::Reinstall < ::TransactionChain
    label 'Reinstall'

    def link_chain(vps, template, opts)
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

      reinstall_vpsadminos(vps, template)

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key], reversible: :keep_going)
      end

      if opts[:vps_user_data]
        append_t(
          Transactions::Vps::DeployUserData,
          args: [vps, opts[:vps_user_data]],
          kwargs: { os_template: template }
        )

        apply_user_data = template.apply_user_data?(opts[:vps_user_data])
      end

      # Set reversible to :keep_going, because we cannot be certain that
      # the template is correct and the VPS will start.
      use_chain(Vps::Start, args: vps, reversible: :keep_going) if running || apply_user_data

      return unless apply_user_data

      append_t(
        Transactions::Vps::ApplyUserData,
        args: [vps, opts[:vps_user_data]],
        kwargs: { os_template: template }
      )
    end

    def reinstall_vpsadminos(vps, template)
      # Remove all local snapshots
      vps.dataset_in_pool.snapshot_in_pools.each do |sip|
        use_chain(SnapshotInPool::Destroy, args: sip)
      end

      # Detach all backup heads
      use_chain(DatasetInPool::DetachBackupHeads, args: vps.dataset_in_pool)

      # Reinstall CT
      append_t(Transactions::Vps::Reinstall, args: [vps, template]) do |t|
        t.edit(vps, os_template_id: template.id)
        t.increment(vps.dataset_in_pool.dataset, 'current_history_id')
      end

      # Reconfigure features (currently because of NixOS impermanence, which would get
      # turned on when the container image config is reapplied)
      use_chain(Vps::Features, args: [vps, vps.vps_features])
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
        ).where(pools: { is_open: true }).each do |dst|
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
