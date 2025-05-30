module TransactionChains
  class User::HardDelete < ::TransactionChain
    label 'Hard delete user'

    def link_chain(user, _target, _state, _log)
      # Destroy all exports
      user.exports.each do |ex|
        ex.set_object_state(
          :deleted,
          reason: 'User was hard deleted',
          chain: self
        )
      end

      # Destroy all VPSes
      user.vpses.where(object_state: [
                         ::Vps.object_states[:active],
                         ::Vps.object_states[:suspended],
                         ::Vps.object_states[:soft_delete]
                       ]).each do |vps|
        vps.set_object_state(
          :hard_delete,
          reason: 'User was hard deleted',
          chain: self
        )
      end

      # Destroy all datasets
      user.datasets.all.order('full_name DESC').each do |ds|
        dip = ds.primary_dataset_in_pool!

        if dip.pool.role == 'hypervisor'
          # VPS datasets are already deleted but from hypervisor pools only,
          # we have to take care about backups.
          ds.dataset_in_pools.joins(:pool).where(
            pools: { role: ::Pool.roles[:backup] }
          ).each do |backup|
            use_chain(DatasetInPool::Destroy, args: [backup, { recursive: true }])
          end

        else # primary pool, delete right away with all backups
          ds.set_object_state(:deleted, chain: self)
        end
      rescue ActiveRecord::RecordNotFound
        # The dataset is not present on any primary/hypervisor pool as it has
        # been already deleted and exists only in backup.

        ds.set_object_state(:deleted, chain: self)
      end

      # Destroy snapshot downloads
      user.snapshot_downloads.each do |dl|
        use_chain(Dataset::RemoveDownload, args: dl)
      end

      # Destroy owned DNS records
      user.dns_records.joins(:dns_zone).each do |r|
        use_chain(DnsZone::DestroyRecord, args: [r])
      end

      # Destroy DNS zones
      user.dns_zones.each do |dns_zone|
        use_chain(DnsZone::DestroyUser, args: [dns_zone])
      end

      # Free user namespaces
      user.user_namespaces.each do |userns|
        use_chain(UserNamespace::Free, args: userns)
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        # Free all IP addresses
        user.environment_user_configs.each do |cfg|
          cfg.free_resources(chain: self, free_objects: true).each do |use|
            t.destroy(use)
          end
        end

        # TODO: what about owned networks?

        # Delete TSIG keys
        user.dns_tsig_keys do |tsig_key|
          t.just_destroy(tsig_key)
        end

        # Delete all public keys
        user.user_public_keys.each do |key|
          t.just_destroy(key)
        end

        user.vps_user_data.each do |data|
          t.just_destroy(data)
        end

        # Remove TOTP devices
        user.user_totp_devices.each do |dev|
          t.just_destroy(dev)
        end

        # Remove WebAuthn credentials
        user.webauthn_credentials.each do |cred|
          t.just_destroy(cred)
        end

        # Free the login and forget password
        t.edit(user, login: nil, orig_login: user.login, password: '!')
      end
    end
  end
end
