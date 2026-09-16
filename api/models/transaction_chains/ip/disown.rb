module TransactionChains
  # Shared cleanup and accounting for a complete set of owned allocations.
  class Ip::Disown < ::TransactionChain
    label 'Disown IPs'
    allow_empty

    def link_chain(ips:, defer: false)
      ips = ips.uniq(&:id).sort_by(&:id)
      ::IpAddress.lock_all_current!(self, ips)
      ips.each(&:ensure_charge_environment!)
      groups = ips.select(&:user_id).group_by do |ip|
        [ip.user_id, ip.charged_environment_id, ip.cluster_resource]
      end
      configs = groups.keys.to_h do |owner_id, environment_id, resource_id|
        [[owner_id, environment_id, resource_id],
         ::EnvironmentUserConfig.find_by!(user_id: owner_id, environment_id:)]
      end
      configs.values.uniq(&:id).sort_by(&:id).each(&:lock!)

      before_cleanup = last_id
      use_chain(NetworkInterface::CleanupHostIpAddresses, kwargs: { ips:, delete: true })
      deferred = defer || last_id != before_cleanup
      # Each deferred usage total must be calculated once, even when several
      # allocations share it. Confirmation edits contain absolute totals.
      uses = groups.sort.map do |key, addresses|
        configs.fetch(key).adjust_resource!(
          addresses.first.cluster_resource, delta: -addresses.sum { |ip| ip.size.to_i },
                                            user: addresses.first.user, save: !deferred, chain: deferred ? self : nil,
                                            confirmed: ::ClusterResourceUse.confirmed(:confirmed)
        )
      end
      unless deferred
        ips.each { |ip| ip.update!(user: nil, charged_environment: nil) }
        return
      end

      confirmation = nil
      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        ips.each { |ip| t.edit(ip, user_id: nil, charged_environment_id: nil) }
        uses.each { |use| t.edit(use, value: use.value) }
        confirmation = t
      end
      confirmation
    end
  end
end
