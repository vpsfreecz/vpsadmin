# frozen_string_literal: true

module NodeCtldSpec
  module BaselineSeed
    class << self
      attr_reader :ids

      def bootstrap!
        return if @bootstrapped

        raw = ActiveRecord::Base.connection.raw_connection
        now = Time.now.utc

        @ids = {}

        env_id = insert(raw, 'environments', {
          label: 'Spec Env',
          domain: 'spec.test',
          created_at: now,
          updated_at: now,
          maintenance_lock: 0,
          can_create_vps: 0,
          can_destroy_vps: 0,
          vps_lifetime: 0,
          max_vps_count: 10,
          user_ip_ownership: 0,
          description: 'libnodectld spec environment'
        })

        loc_id = insert(raw, 'locations', {
          label: 'Spec Location',
          has_ipv6: 1,
          remote_console_server: '',
          domain: 'loc.spec.test',
          created_at: now,
          updated_at: now,
          maintenance_lock: 0,
          environment_id: env_id,
          description: 'libnodectld spec location'
        })

        node_id = insert(raw, 'nodes', {
          name: 'spec-node-a',
          location_id: loc_id,
          ip_addr: '192.0.2.101',
          max_vps: 10,
          max_tx: 235_929_600,
          max_rx: 235_929_600,
          maintenance_lock: 0,
          cpus: 4,
          total_memory: 4096,
          total_swap: 1024,
          role: 0,
          hypervisor_type: 1,
          active: 1
        })

        cluster_resource_id = insert(raw, 'cluster_resources', {
          name: 'cpu',
          label: 'CPU',
          min: 0,
          max: 1_000_000,
          stepsize: 1,
          resource_type: 0
        })

        user_cluster_resource_id = insert(raw, 'user_cluster_resources', {
          user_id: nil,
          environment_id: env_id,
          cluster_resource_id: cluster_resource_id,
          value: 1000
        })

        @ids[:environment_id] = env_id
        @ids[:location_id] = loc_id
        @ids[:node_id] = node_id
        @ids[:cluster_resource_id] = cluster_resource_id
        @ids[:user_cluster_resource_id] = user_cluster_resource_id
        @bootstrapped = true
      end

      private

      def insert(raw, table, attrs)
        cols = attrs.keys.map { |k| "`#{k}`" }.join(', ')
        placeholders = Array.new(attrs.size, '?').join(', ')

        stmt = raw.prepare(
          "INSERT INTO #{table} (#{cols}) VALUES (#{placeholders})"
        )
        stmt.execute(*attrs.values)
        raw.last_id
      ensure
        stmt&.close
      end
    end
  end
end
