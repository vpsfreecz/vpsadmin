module TransactionChains
  class User::HardDelete < ::TransactionChain
    label 'Hard delete user'

    def link_chain(user, _target, _state, _log)
      # Keep ownership and its accounting evidence until legacy charges are reconciled.
      ::IpAddress.where(user:, charged_environment_id: nil).lock.take&.ensure_charge_environment!

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

      user.user_sessions.where(closed_at: nil).each(&:close!)
      user.single_sign_ons.destroy_all
      user.oauth2_authorizations.destroy_all
      user.metrics_access_tokens.destroy_all
      ::PasswordChangeLog.where(user:).delete_all

      # Link cleanup first so quota destruction depends on its completion.
      resource_uses = user.environment_user_configs.flat_map do |cfg|
        cfg.free_resources(chain: self, free_objects: true)
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        resource_uses.each { |use| t.destroy(use) }

        # TODO: what about owned networks?

        # Delete TSIG keys
        user.dns_tsig_keys.each do |tsig_key|
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
