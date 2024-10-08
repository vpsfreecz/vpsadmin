require 'prometheus/client'
require 'prometheus/client/formats/text'

module VpsAdmin::API::Tasks
  class Prometheus < Base
    EXPORT_FILE = ENV['EXPORT_FILE'] || '/run/metrics/vpsadmin.prom'

    DNS_ZONE_LABELS = %i[dns_zone dns_source dns_role].freeze

    DNS_SERVER_ZONE_LABELS = (DNS_ZONE_LABELS + %i[dns_server dns_type]).freeze

    def initialize
      super
      @registry = ::Prometheus::Client.registry

      @user_count = registry.gauge(
        :vpsadmin_user_count,
        docstring: 'The number of vpsAdmin users',
        labels: [:object_state]
      )

      @vps_count = registry.gauge(
        :vpsadmin_vps_count,
        docstring: 'The number of VPS in vpsAdmin',
        labels: %i[
          object_state vps_node vps_platform vps_location
          distribution_template distribution_name distribution_version
        ]
      )

      @dataset_count = registry.gauge(
        :vpsadmin_dataset_count,
        docstring: 'The number of datasets in vpsAdmin',
        labels: %i[dataset_role dataset_node dataset_location]
      )

      @snapshot_count = registry.gauge(
        :vpsadmin_snapshot_count,
        docstring: 'The number of snapshots in vpsAdmin',
        labels: %i[snapshot_role snapshot_node snapshot_location]
      )

      @node_last_report_seconds = registry.gauge(
        :vpsadmin_node_last_report_seconds,
        docstring: 'The number of seconds since the node last reported',
        labels: %i[node_name node_location node_platform]
      )

      @transaction_chain_state_seconds = registry.gauge(
        :vpsadmin_transaction_chain_queued_seconds,
        docstring: 'Number of seconds a chain has been in a run state',
        labels: %i[chain_id chain_type chain_state]
      )

      @transaction_chain_fatal = registry.gauge(
        :vpsadmin_transaction_chain_fatal,
        docstring: 'Set when a transaction chains ends up in state fatal',
        labels: %i[chain_id chain_type]
      )

      @transaction_chain_count = registry.gauge(
        :vpsadmin_transaction_chain_count,
        docstring: 'Numbers of transaction chains by type and state',
        labels: %i[chain_type chain_state]
      )

      @dataset_expansion_count = registry.gauge(
        :vpsadmin_dataset_expansion_count,
        docstring: 'Number of dataset expansions',
        labels: %i[vps_location vps_node vps_id dataset_name]
      )

      @dataset_expansion_added_bytes = registry.gauge(
        :vpsadmin_dataset_expansion_added_bytes,
        docstring: 'Amount of space added by expansion in bytes',
        labels: %i[vps_location vps_node vps_id dataset_name]
      )

      @dataset_expansion_seconds = registry.gauge(
        :vpsadmin_dataset_expansion_seconds,
        docstring: 'Number of seconds the dataset is expanded',
        labels: %i[vps_location vps_node vps_id dataset_name]
      )

      @dataset_expansion_over_refquota_seconds = registry.gauge(
        :vpsadmin_dataset_expansion_over_refquota_seconds,
        docstring: 'Number of seconds over refquota',
        labels: %i[vps_location vps_node vps_id dataset_name]
      )

      @dataset_expansion_max_over_refquota_seconds = registry.gauge(
        :vpsadmin_dataset_expansion_max_over_refquota_seconds,
        docstring: 'Maximum number of seconds over refquota',
        labels: %i[vps_location vps_node vps_id dataset_name]
      )

      @export_host_ip_owner_mismatch = registry.gauge(
        :vpsadmin_export_host_ip_owner_mismatch,
        docstring: 'Export host with mismatching IP owner',
        labels: %i[user_id export_id ip_address_id ip_address_addr]
      )

      @vps_incident_report_count = registry.gauge(
        :vpsadmin_vps_incident_report_count,
        docstring: 'Number of incident reports per VPS',
        labels: %i[vps_id user_id]
      )

      @dns_zone_enabled = registry.gauge(
        :vpsadmin_dns_zone_enabled,
        docstring: '1 if the DNS zone is enabled, 0 otherwise',
        labels: DNS_ZONE_LABELS
      )

      @dns_zone_dnssec_enabled = registry.gauge(
        :vpsadmin_dns_zone_dnssec_enabled,
        docstring: '1 if the DNSSEC is enabled on internal zone, 0 otherwise',
        labels: DNS_ZONE_LABELS
      )

      @dns_zone_default_ttl = registry.gauge(
        :vpsadmin_dns_zone_default_ttl,
        docstring: 'Default TTL for records in internal zones in seconds',
        labels: DNS_ZONE_LABELS
      )

      @dns_zone_record_count = registry.gauge(
        :vpsadmin_dns_zone_record_count,
        docstring: 'Number of records in internal DNS zone',
        labels: DNS_ZONE_LABELS + %i[record_type]
      )

      @dns_server_zone_last_check_at = registry.gauge(
        :vpsadmin_dns_server_zone_last_check_at,
        docstring: 'Time when DNS zone status was last checked',
        labels: DNS_SERVER_ZONE_LABELS
      )

      @dns_server_zone_serial = registry.gauge(
        :vpsadmin_dns_server_zone_serial,
        docstring: 'DNS zone serial number',
        labels: DNS_SERVER_ZONE_LABELS
      )

      @dns_server_zone_loaded_at = registry.gauge(
        :vpsadmin_dns_server_zone_loaded_at,
        docstring: 'Time when DNS zone was last loaded',
        labels: DNS_SERVER_ZONE_LABELS
      )

      @dns_server_zone_expires_at = registry.gauge(
        :vpsadmin_dns_server_zone_expires_at,
        docstring: 'Time when secondary DNS zone expires',
        labels: DNS_SERVER_ZONE_LABELS
      )

      @dns_server_zone_refresh_at = registry.gauge(
        :vpsadmin_dns_server_zone_refresh_at,
        docstring: 'Time when secondary DNS zone will be refreshed',
        labels: DNS_SERVER_ZONE_LABELS
      )
    end

    # Export metrics for Prometheus
    #
    # Accepts the following environment variables:
    # [EXPORT_FILE]: File where the metrics are written to
    def export
      # user_count
      ::User
        .unscoped
        .where.not(object_state: 'hard_delete')
        .group(:object_state)
        .count
        .each do |state, cnt|
        @user_count.set(
          cnt,
          labels: { object_state: state }
        )
      end

      # vps_count
      vps_count_result = ::Vps
                         .unscoped
                         .joins(:os_template, node: :location)
                         .where.not(object_state: 'hard_delete')
                         .group(
                           'vpses.object_state',
                           'os_templates.name',
                           'os_templates.distribution',
                           'os_templates.version',
                           'nodes.name',
                           'nodes.hypervisor_type',
                           'locations.domain'
                         ).count

      vps_count_result.each do |grp, cnt|
        state, tpl_name, tpl_dist, tpl_ver, node, hypervisor_type_val, location = grp

        hypervisor_type = ::Node.hypervisor_types.key(hypervisor_type_val)

        @vps_count.set(cnt, labels: {
                         object_state: state,
                         distribution_template: tpl_name,
                         distribution_name: tpl_dist,
                         distribution_version: tpl_ver,
                         vps_node: [node, location].join('.'),
                         vps_platform: hypervisor_type,
                         vps_location: location
                       })
      end

      # dataset_count
      dataset_count_result = ::DatasetInPool
                             .joins(pool: { node: :location })
                             .group('pools.role', 'nodes.name', 'locations.domain')
                             .count

      dataset_count_result.each do |grp, cnt|
        role, node, location = grp

        @dataset_count.set(cnt, labels: {
                             dataset_role: ::Pool.roles.key(role),
                             dataset_node: [node, location].join('.'),
                             dataset_location: location
                           })
      end

      # snapshot_count
      snapshot_count_result = ::SnapshotInPool
                              .joins(dataset_in_pool: { pool: { node: :location } })
                              .group('pools.role', 'nodes.name', 'locations.domain')
                              .count

      snapshot_count_result.each do |grp, cnt|
        role, node, location = grp

        @snapshot_count.set(cnt, labels: {
                              snapshot_role: ::Pool.roles.key(role),
                              snapshot_node: [node, location].join('.'),
                              snapshot_location: location
                            })
      end

      # node_last_report_seconds
      t_now = Time.now

      ::Node
        .joins(:node_current_status)
        .includes(:node_current_status, :location)
        .where(active: true)
        .each do |node|
        last_report = node.node_current_status.updated_at \
                      || node.node_current_status.created_at

        @node_last_report_seconds.set(t_now - last_report, labels: {
                                        node_name: node.domain_name,
                                        node_location: node.location.domain,
                                        node_platform: node.hypervisor_type
                                      })
      end

      # transaction_chain_state_seconds
      ::TransactionChain.where(state: %w[queued rollbacking]).each do |chain|
        @transaction_chain_state_seconds.set(
          (Time.now - chain.updated_at).round,
          labels: {
            chain_id: chain.id,
            chain_type: chain.type.to_s,
            chain_state: chain.state
          }
        )
      end

      # transaction_chain_fatal
      ::TransactionChain.where(state: 'fatal').each do |chain|
        @transaction_chain_fatal.set(1, labels: {
                                       chain_id: chain.id,
                                       chain_type: chain.type.to_s
                                     })
      end

      # transaction_chain_count
      ::TransactionChain.group('type', 'state').count.each do |grp, cnt|
        type, state = grp
        @transaction_chain_count.set(cnt, labels: {
                                       chain_type: type,
                                       chain_state: state
                                     })
      end

      # dataset_expansion_*
      ::DatasetExpansion
        .includes(:dataset, vps: { node: :location })
        .joins(:vps, dataset: :user)
        .where(state: 'active')
        .where(users: { object_state: ::User.object_states[:active] })
        .where(vpses: { object_state: ::Vps.object_states[:active] })
        .each do |exp|
        labels = {
          vps_location: exp.vps.node.location.domain,
          vps_node: exp.vps.node.domain_name,
          vps_id: exp.vps.id,
          dataset_name: exp.dataset.full_name
        }

        @dataset_expansion_count.set(
          exp.expansion_count,
          labels:
        )

        @dataset_expansion_added_bytes.set(
          exp.added_space * 1024 * 1024,
          labels:
        )

        @dataset_expansion_seconds.set(
          t_now - exp.created_at,
          labels:
        )

        @dataset_expansion_over_refquota_seconds.set(
          exp.over_refquota_seconds,
          labels:
        )

        @dataset_expansion_max_over_refquota_seconds.set(
          exp.max_over_refquota_seconds,
          labels:
        )
      end

      # export_host_ip_owner_mismatch
      export_hosts = []

      # IPs not owned by a user, only assigned to a VPS
      export_hosts.concat(
        ::ExportHost
          .includes(:export, :ip_address)
          .joins(:export, ip_address: { network_interface: :vps })
          .where('vpses.user_id != exports.user_id')
          .to_a
      )

      # IPs owned by a user
      export_hosts.concat(
        ::ExportHost
          .includes(:export, :ip_address)
          .joins(:export, :ip_address)
          .where('ip_addresses.user_id IS NOT NULL AND ip_addresses.user_id != exports.user_id')
          .to_a
      )

      export_hosts.uniq(&:id).each do |host|
        @export_host_ip_owner_mismatch.set(
          1,
          labels: {
            user_id: host.export.user_id,
            export_id: host.export_id,
            ip_address_id: host.ip_address_id,
            ip_address_addr: host.ip_address.to_s
          }
        )
      end

      # vps_incident_report_count
      ::IncidentReport
        .joins(:vps)
        .where(vpses: { object_state: ::Vps.object_states[:active] })
        .group(:user_id, :vps_id)
        .count
        .each do |arr, cnt|
          user_id, vps_id = arr

          @vps_incident_report_count.set(
            cnt,
            labels: { user_id:, vps_id: }
          )
        end

      ::DnsZone.all.each do |zone|
        labels = { dns_zone: zone.name, dns_source: zone.zone_source, dns_role: zone.zone_role }

        @dns_zone_enabled.set(zone.enabled ? 1 : 0, labels:)
        next if zone.external_source?

        @dns_zone_dnssec_enabled.set(zone.dnssec_enabled ? 1 : 0, labels:)
        @dns_zone_default_ttl.set(zone.default_ttl, labels:)

        zone.dns_records.group('record_type').count.each do |type, cnt|
          @dns_zone_record_count.set(cnt, labels: labels.merge(record_type: type))
        end
      end

      ::DnsServerZone
        .includes(:dns_zone, :dns_server)
        .joins(:dns_zone)
        .where(dns_zones: { enabled: true })
        .each do |server_zone|
        labels = {
          dns_server: server_zone.dns_server.name,
          dns_zone: server_zone.dns_zone.name,
          dns_source: server_zone.dns_zone.zone_source,
          dns_role: server_zone.dns_zone.zone_role,
          dns_type: server_zone.zone_type
        }

        @dns_server_zone_last_check_at.set(server_zone.last_check_at.to_i, labels:)
        @dns_server_zone_serial.set(server_zone.serial.to_i, labels:)
        @dns_server_zone_loaded_at.set(server_zone.loaded_at.to_i, labels:)

        next if server_zone.primary_type?

        @dns_server_zone_expires_at.set(server_zone.expires_at.to_i, labels:)
        @dns_server_zone_refresh_at.set(server_zone.refresh_at.to_i, labels:)
      end

      save
    end

    protected

    attr_reader :registry

    def save
      tmp = "#{EXPORT_FILE}.new"

      File.write(tmp, ::Prometheus::Client::Formats::Text.marshal(registry))

      File.rename(tmp, EXPORT_FILE)
    end
  end
end
