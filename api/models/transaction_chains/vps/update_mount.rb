module TransactionChains
  class Vps::UpdateMount < ::TransactionChain
    label 'Mount*'

    def link_chain(mount, attrs)
      lock(mount.vps)
      concerns(:affect, [mount.vps.class.name, mount.vps.id])

      mount.assign_attributes(attrs)
      changes = mount.changes

      do_umount = (mount.enabled_changed? && !mount.enabled) \
                  || (mount.master_enabled_changed? && !mount.master_enabled)
      do_mount  = (mount.enabled_changed? || mount.master_enabled_changed?) \
                  && (mount.enabled && mount.master_enabled)

      mount.save!

      use_chain(Vps::Mounts, args: mount.vps)

      use_chain(Vps::Umount, args: [mount.vps, [mount]]) if do_umount
      use_chain(Vps::Mount, args: [mount.vps, [mount]]) if do_mount

      append(Transactions::Utils::NoOp, args: find_node_id) do
        changes.each do |k, v|
          case k.to_sym
          when :enabled, :master_enabled
            edit_before(mount, k => (v.first ? 1 : 0))

          when :on_start_fail
            edit_before(mount, k => ::Mount.on_start_fails[v.first])

          else
            fail "unsupported attribute '#{k}'"
          end
        end
      end
    end
  end
end
