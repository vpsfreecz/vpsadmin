require 'prometheus/client'
require 'prometheus/client/formats/text'

module VpsAdmin::API::Tasks
  class Prometheus < Base
    EXPORT_FILE = ENV['EXPORT_FILE'] || '/run/metrics/vpsadmin.prom'

    def initialize
      @registry = ::Prometheus::Client.registry

      @user_count = registry.gauge(
        :vpsadmin_user_count,
        docstring: 'The number of vpsAdmin users',
        labels: [:object_state],
      )

      @vps_count = registry.gauge(
        :vpsadmin_vps_count,
        docstring: 'The number of VPS in vpsAdmin',
        labels: [
          :object_state, :node, :hypervisor_type, :location,
          :distribution_template, :distribution_name, :distribution_version,
        ],
      )

      @dataset_count = registry.gauge(
        :vpsadmin_dataset_count,
        docstring: 'The number of datasets in vpsAdmin',
        labels: [:role, :node, :location],
      )

      @snapshot_count = registry.gauge(
        :vpsadmin_snapshot_count,
        docstring: 'The number of snapshots in vpsAdmin',
        labels: [:role, :node, :location],
      )

      @transaction_chain_state_seconds = registry.gauge(
        :vpsadmin_transaction_chain_queued_seconds,
        docstring: 'Number of seconds a chain has been in a run state',
        labels: [:chain_id, :chain_type, :chain_state],
      )

      @transaction_chain_fatal = registry.gauge(
        :vpsadmin_transaction_chain_fatal,
        docstring: 'Set when a transaction chains ends up in state fatal',
        labels: [:chain_id, :chain_type],
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
          labels: {object_state: state},
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

        if hypervisor_type == 'openvz'
          tpl_dist, tpl_ver, _ = tpl_name.split('-')
        end

        @vps_count.set(cnt, labels: {
          object_state: state,
          distribution_template: tpl_name,
          distribution_name: tpl_dist,
          distribution_version: tpl_ver,
          node: [node, location].join('.'),
          hypervisor_type: hypervisor_type,
          location: location,
        })
      end

      # dataset_count
      dataset_count_result = ::DatasetInPool
        .joins(pool: {node: :location})
        .group('pools.role', 'nodes.name', 'locations.domain')
        .count

      dataset_count_result.each do |grp, cnt|
        role, node, location = grp

        @dataset_count.set(cnt, labels: {
          role: ::Pool.roles.key(role),
          node: [node, location].join('.'),
          location: location,
        })
      end

      # snapshot_count
      snapshot_count_result = ::SnapshotInPool
        .joins(dataset_in_pool: {pool: {node: :location}})
        .group('pools.role', 'nodes.name', 'locations.domain')
        .count

      snapshot_count_result.each do |grp, cnt|
        role, node, location = grp

        @snapshot_count.set(cnt, labels: {
          role: ::Pool.roles.key(role),
          node: [node, location].join('.'),
          location: location,
        })
      end

      # transaction_chain_state_seconds
      ::TransactionChain.where(state: ['queued', 'rollbacking']).each do |chain|
        @transaction_chain_state_seconds.set(
          (Time.now - chain.updated_at).round,
          labels: {
            chain_id: chain.id,
            chain_type: chain.type.to_s,
            chain_state: chain.state,
          },
        )
      end

      # transaction_chain_fatal
      ::TransactionChain.where(state: 'fatal').each do |chain|
        @transaction_chain_fatal.set(1, labels: {
          chain_id: chain.id,
          chain_type: chain.type.to_s,
        })
      end

      save
    end

    protected
    attr_reader :registry

    def save
      tmp = "#{EXPORT_FILE}.new"

      File.open(tmp, 'w') do |f|
        f.write(::Prometheus::Client::Formats::Text.marshal(registry))
      end

      File.rename(tmp, EXPORT_FILE)
    end
  end
end
