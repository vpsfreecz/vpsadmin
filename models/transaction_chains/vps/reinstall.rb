module TransactionChains
  class Vps::Reinstall < ::TransactionChain
    label 'Reinstall VPS'

    def link_chain(vps, template)
      lock(vps.dataset_in_pool)
      lock(vps)

      # Destroy all subdatasets on hypervisor with all their snapshots
      # Set head = false for all trees

      children = destroy_child_datasets(vps.dataset_in_pool.dataset)
      trees = reset_backups(vps.dataset_in_pool.dataset)

      # Would be better to split this to two transactions - destroy and create,
      # so that the database would be more consistent. Now the datasets can
      # be destroyed on hypervisor, but creation fails and boom, they stay
      # in the database.
      # But it's hard to simulate vpsAdmind's honor_state method
      # with the way transactions work at the moment...
      append(Transactions::Vps::Reinstall, args: [vps, template]) do
        edit(vps, vps_template: template.id)

        children[:snapshots].each { |s| destroy(s) }
        children[:datasets].each { |dip| destroy(dip) }
        trees.each { |t| edit(t, head: false) }
      end

      append(Transactions::Vps::ApplyConfig, args: vps)
      # FIXME: regenerate mounts
    end

    def destroy_child_datasets(dataset, top = true)
      ret = {datasets: [], snapshots: []}

      qs = ::DatasetInPool
        .joins(:dataset, :pool)
        .where(pools: {role: Pool.roles[:hypervisor]})

      if top
        qs = qs.where(datasets: {id: dataset.id})
      else
        qs = qs.where(datasets: {parent_id: dataset.id})
      end

      qs.each do |dip|

        lock(dip)

        children = destroy_child_datasets(dip.dataset, false)

        ret[:datasets].concat(children[:datasets])
        ret[:snapshots].concat(children[:snapshots])

        # Keep the top-level dataset
        ret[:datasets] << dip unless top

        dip.snapshot_in_pools.all.each do |s|
          ret[:snapshots] << s
        end

      end

      ret
    end

    def reset_backups(dataset, top = true)
      ret = []

      qs = ::DatasetTree
        .joins(dataset_in_pool: [:dataset, :pool])
        .where(
            pools: {role: Pool.roles[:backup]},
            head: true
       )

      if top
        qs = qs.where(datasets: {id: dataset.id})
      else
        qs = qs.where(datasets: {parent_id: dataset.id})
      end

      qs.each do |tree|

        lock(tree.dataset_in_pool)

        ret.concat(reset_backups(tree.dataset_in_pool.dataset, false))
        ret << tree

      end

      ret
    end
  end
end
