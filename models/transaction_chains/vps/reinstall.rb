module TransactionChains
  class Vps::Reinstall < ::TransactionChain
    label 'Reinstall VPS'

    # FIXME: reinstall destroys snapshots that may not have been backed up!
    def link_chain(vps, template)
      lock(vps.dataset_in_pool)
      lock(vps)

      running = vps.running?

      # Send the stop nevertheless, vpsAdmin information about VPS
      # status may not be up-to-date.
      use_chain(Vps::Stop, args: vps)

      # Destroy underlying dataset with all its descendants,
      # but do not delete the top-level dataset from database.
      use_chain(DatasetInPool::Destroy, args: [vps.dataset_in_pool, true, false])

      # Destroy VPS configs, mounts, root
      append(Transactions::Vps::Destroy, args: vps)

      # Create the dataset again
      append(Transactions::Storage::CreateDataset, args: vps.dataset_in_pool)

      # Create VPS
      append(Transactions::Vps::Create, args: vps) do
        edit(vps, vps_template: template.id)

        # Reset features
        vps.vps_features.each do |f|
          edit(f, enabled: 0)
        end
      end

      append(Transactions::Vps::ApplyConfig, args: vps)
      use_chain(Vps::Mounts, args: vps)

      vps.ip_addresses.all.each do |ip|
        append(Transactions::Vps::IpAdd, args: [vps, ip])
      end

      if running
        use_chain(Vps::Start, args: vps)
      end
    end
  end
end
