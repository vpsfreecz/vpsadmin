module TransactionChains
  class DnsServer::Update < ::TransactionChain
    label 'Update DNS server'
    allow_empty

    def link_chain(server, attrs)
      lock(server)
      # This action is a root operation: its discovery view begins after the
      # parent reservation. Do not hold server SQL locks while reserving zones.
      server.reload
      server.assign_attributes(attrs)
      raise ActiveRecord::RecordInvalid, server unless server.valid?

      original_server_attrs = server.changes.transform_values(&:first)
      changed_ip_versions = []
      changed_ip_versions << 4 if server.ipv4_addr_changed?
      changed_ip_versions << 6 if server.ipv6_addr_changed?
      if changed_ip_versions.empty?
        server.reload(lock: true)
        server.assign_attributes(attrs)
        server.save!
        return server
      end

      # Discovery includes pending associations: their owning chain must block
      # this change even when its rollback can make the zone visible again.
      zones = server.dns_zones.external_source.distinct.order(:id).to_a
      zones.each { |zone| lock(zone) }
      configuration = ::DnsServerZone.lock_configuration(zones, servers: [server])
      zones = configuration.fetch(:zones).select { |zone| %i[confirm_create confirmed].include?(zone.confirmed) }
      server = configuration.fetch(:servers).find { |entry| entry.id == server.id }
      originals = zones.to_h do |zone|
        [zone.id, zone.attributes.slice('primary_transfer_generation', 'primary_transfer_tracking_started_at')]
      end
      server_zones = configuration.fetch(:server_zones).select { |entry| zones.include?(entry.dns_zone) }
      original_configs = server_zones.to_h do |server_zone|
        [server_zone.id, server_zone.configuration_attrs(**configuration)]
      end
      server.assign_attributes(attrs)
      original_server_attrs = server.changes.transform_values(&:first)

      concerns(:affect, [server.class.name, server.id], *zones.map { |zone| [zone.class.name, zone.id] })
      server.save!
      zones.each(&:rotate_primary_transfer_generation!)
      reset_changed_source_states(server_zones.select { |entry| entry.dns_server_id == server.id }, changed_ip_versions)

      server_zones.each do |server_zone|
        use_chain(
          DnsServerZone::RefreshConfiguration,
          args: [server_zone],
          kwargs: { original: original_configs.fetch(server_zone.id), configuration: }
        )
      end
      return server if empty?

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.edit_before(server, original_server_attrs)
        zones.each { |zone| t.edit_before(zone, originals.fetch(zone.id)) }
      end
      server
    end

    protected

    def reset_changed_source_states(server_zones, changed_ip_versions)
      server_zones.each do |server_zone|
        server_zone.with_lock do
          state_ids = server_zone.dns_server_zone_primary_transfer_states
                                 .lock
                                 .includes(dns_zone_transfer: :host_ip_address)
                                 .filter_map do |state|
            addr = ::IPAddress.parse(state.dns_zone_transfer.ip_addr)
            state.id if changed_ip_versions.include?(addr.ipv4? ? 4 : 6)
          end
          ::DnsServerZonePrimaryTransferState.where(id: state_ids).delete_all
        end
      end
    end
  end
end
