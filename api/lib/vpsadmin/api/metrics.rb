require 'prometheus/client'
require 'prometheus/client/formats/text'

module VpsAdmin::API
  class Metrics
    # Bump version when metrics, labels or the meaning of values changes
    VERSION = 1.0

    NODE_LABELS = %i[node_id node_name location_id location_label].freeze

    POOL_LABELS = (NODE_LABELS + %i[pool_id pool_name]).freeze

    VPS_LABELS = %i[vps_id node_id node_name location_id location_label].freeze

    NETACC_LABELS = (VPS_LABELS + %i[netif_id netif_name year month direction]).freeze

    DATASET_LABELS = %i[
      node_id node_name
      location_id location_label
      pool_id pool_name
      dataset_id dataset_name
    ].freeze

    INCIDENT_REPORT_LABELS = (VPS_LABELS + %i[codename]).freeze

    OOM_REPORT_LABELS = (VPS_LABELS + %i[invoked_by_name killed_name]).freeze

    # NOTE: Only 5 minute load average is saved by the supervisor
    LOADAVGS = [5].freeze

    CPU_USAGE_STATS = %i[idle system user].freeze

    DATASET_PROPERTIES = {
      used: :used_bytes,
      referenced: :referenced_bytes,
      avail: :available_bytes,
      compressratio: :compressratio,
      refcompressratio: :refcompressratio,
      quota: :quota_bytes,
      refquota: :refquota_bytes
    }.freeze

    DATASET_PROPERTIES_IN_BYTES = %i[used referenced avail quota refquota].freeze

    def initialize
      @registry = Prometheus::Client::Registry.new
    end

    # @param access_token [String]
    # @return [Boolean]
    def authenticate(access_token)
      @token = ::MetricsAccessToken.joins(:token).where(tokens: { token: access_token }).take
      return false if @token.nil? || !%w[active suspended].include?(@token.user.object_state)

      @token.increment(:use_count)
      @token.update!(last_use: Time.now)

      setup

      true
    end

    def compute
      @version.set(VERSION)

      user = @token.user
      vpses = user.vpses.includes(node: :location).where(object_state: %w[active suspended]).to_a
      vps_index = vpses.to_h { |vps| [vps.id, vps] }

      ::Node.includes(:location).where(active: true).each do |node|
        labels = node_labels(node)

        @node_status.set(node.status ? 1 : 0, labels:)
        @node_cpu_idle.set(node.cpu_idle || 100.0, labels:)
        @node_maintenance.set(node.maintenance_lock? == :no ? 0 : 1, labels:)
      end

      ::Pool.includes(node: :location).joins(:node).where(nodes: { active: true }).each do |pool|
        labels = pool_labels(pool)

        @pool_state.set(::Pool.states[pool.state], labels:)
        @pool_scan.set(::Pool.scans[pool.scan], labels:)
        @pool_scan_percent.set(pool.scan_percent || 0.0, labels:)
      end

      vpses.each do |vps|
        labels = vps_labels(vps)

        @vps_is_running.set(vps.running? ? 1 : 0, labels:)
        @vps_in_rescue_mode.set(vps.in_rescue_mode ? 1 : 0, labels:)
        @vps_boot_time_seconds.set(vps.uptime || 0, labels:)

        LOADAVGS.each do |lavg|
          @vps_loadavgs[lavg].set(vps.loadavg || 0, labels:)
        end

        @vps_processes_pids.set(vps.process_count || 0, labels:)

        vps.vps_os_processes.each do |os_procs|
          @vps_processes_state.set(
            os_procs.count,
            labels: labels.merge(state: os_procs.state)
          )
        end

        @vps_memory_used.set(vps.used_memory || 0, labels:)
        @vps_memory_total.set(vps.memory * 1024 * 1024, labels:)

        @vps_swap_used.set(vps.used_swap || 0, labels:)
        @vps_swap_total.set(vps.swap * 1024 * 1024, labels:)

        @vps_cpu_cores.set(vps.cpu, labels:)

        CPU_USAGE_STATS.each do |stat|
          @vps_cpu_usage_percent.set(
            vps.send(:"cpu_#{stat}") || (stat == :idle ? 100 : 0),
            labels: labels.merge(mode: stat)
          )
        end

        vps.vps_features.each do |vps_feature|
          @vps_features.set(
            vps_feature.enabled ? 1 : 0,
            labels: labels.merge(feature: vps_feature.name)
          )
        end

        if vps.expiration_date
          @vps_expiration.set(vps.expiration_date.to_i, labels:)
        end
      end

      ::NetworkInterfaceMonthlyAccounting
        .joins(network_interface: :vps)
        .includes(network_interface: :vps)
        .where(
          vpses: { id: vpses.map(&:id) },
          user_id: user.id
        )
        .each do |acc|
        %i[bytes packets].each do |counter|
          %i[in out].each do |direction|
            @vps_transferred[counter].set(
              acc.send(:"#{counter}_#{direction}"),
              labels: netacc_labels(acc, direction)
            )
          end
        end
      end

      ::DatasetInPool
        .joins(:dataset, :pool)
        .includes(:dataset, :pool)
        .where(
          datasets: { user_id: user.id },
          pools: { role: %w[primary hypervisor] }
        )
        .group(:dataset_id)
        .each do |dip|
        DATASET_PROPERTIES.each_key do |prop|
          v = dip.send(prop)

          if DATASET_PROPERTIES_IN_BYTES.include?(prop)
            v *= 1024 * 1024
          end

          @dataset_properties[prop].set(
            v,
            labels: dataset_labels(dip)
          )
        end
      end

      ::IncidentReport
        .includes(vps: { node: :location })
        .where(vps_id: vpses.map(&:id))
        .group(:vps_id, :codename)
        .count
        .each do |group, cnt|
        vps_id, codename = group

        @incident_reports.set(
          cnt,
          labels: incident_report_labels(vps: vps_index[vps_id], codename:)
        )
      end

      ::OomReport
        .includes(vps: { node: :location })
        .where(vps_id: vpses.map(&:id))
        .group(:vps_id, :invoked_by_name, :killed_name)
        .count
        .each do |group, cnt|
        vps_id, invoked_by_name, killed_name = group

        @oom_reports.set(
          cnt,
          labels: oom_report_labels(vps: vps_index[vps_id], invoked_by_name:, killed_name:)
        )
      end

      user.transaction_chains.group(:state).count.each do |state, cnt|
        @transaction_chains.set(cnt, labels: { state: })
      end

      user.user_sessions.where(closed_at: nil).group(:auth_type).count.each do |auth_type, cnt|
        @user_sessions.set(cnt, labels: { auth_type:, state: 'active' })
      end

      user.user_sessions.where.not(closed_at: nil).group(:auth_type).count.each do |auth_type, cnt|
        @user_sessions.set(cnt, labels: { auth_type:, state: 'closed' })
      end

      user.user_failed_logins.group(:auth_type).count.each do |auth_type, cnt|
        @user_failed_logins.set(cnt, labels: { auth_type: })
      end

      nil
    end

    # @return [String]
    def render
      ::Prometheus::Client::Formats::Text.marshal(@registry)
    end

    protected

    def setup
      @version = add_metric(
        :gauge,
        :metrics_version,
        docstring: 'Version of metrics, labels and their meaning'
      )

      @node_status = add_metric(
        :gauge,
        :node_status,
        docstring: '0 = node is down, 1 = node is online',
        labels: NODE_LABELS
      )

      @node_maintenance = add_metric(
        :gauge,
        :node_maintenance,
        docstring: '0 = node is not under maintenance, 1 = node is under maintenance',
        labels: NODE_LABELS
      )

      @node_cpu_idle = add_metric(
        :gauge,
        :node_cpu_idle_percent,
        docstring: 'CPU idle usage in percent',
        labels: NODE_LABELS
      )

      @pool_state = add_metric(
        :gauge,
        :node_pool_state,
        docstring: '0 = unknown, 1 = online, 2 = degraded, 3 = suspended, 4 = faulted, 5 = error',
        labels: POOL_LABELS
      )

      @pool_scan = add_metric(
        :gauge,
        :node_pool_scan,
        docstring: '0 = unknown, 1 = none, 1 = scrub, 2 = resilver, 3 = error',
        labels: POOL_LABELS
      )

      @pool_scan_percent = add_metric(
        :gauge,
        :node_pool_scan_percent,
        docstring: 'Scan progress in percent',
        labels: POOL_LABELS
      )

      @vps_is_running = add_metric(
        :gauge,
        :vps_is_running,
        docstring: '1 = VPS is running, 0 = VPS is stopped',
        labels: VPS_LABELS
      )

      @vps_in_rescue_mode = add_metric(
        :gauge,
        :vps_in_rescue_mode,
        docstring: '1 = VPS is in rescue mode, 0 = VPS is not in rescue mode',
        labels: VPS_LABELS
      )

      @vps_boot_time_seconds = add_metric(
        :gauge,
        :vps_boot_time_seconds,
        docstring: 'Number of seconds since the VPS was started',
        labels: VPS_LABELS
      )

      @vps_loadavgs = LOADAVGS.to_h do |lavg|
        [
          lavg,
          add_metric(
            :gauge,
            :"vps_load#{lavg}",
            docstring: "#{lavg} minute load average",
            labels: VPS_LABELS
          )
        ]
      end

      @vps_processes_pids = add_metric(
        :gauge,
        :vps_processes_pids,
        docstring: 'Number of processes inside the VPS',
        labels: VPS_LABELS
      )

      @vps_processes_state = add_metric(
        :gauge,
        :vps_processes_state,
        docstring: 'Number of processes and their states',
        labels: VPS_LABELS + %i[state]
      )

      @vps_memory_used = add_metric(
        :gauge,
        :vps_memory_used_bytes,
        docstring: 'Used memory in bytes',
        labels: VPS_LABELS
      )

      @vps_memory_total = add_metric(
        :gauge,
        :vps_memory_total_bytes,
        docstring: 'Total memory in bytes',
        labels: VPS_LABELS
      )

      @vps_swap_used = add_metric(
        :gauge,
        :vps_swap_used_bytes,
        docstring: 'Used swap in bytes',
        labels: VPS_LABELS
      )

      @vps_swap_total = add_metric(
        :gauge,
        :vps_swap_total_bytes,
        docstring: 'Total swap in bytes',
        labels: VPS_LABELS
      )

      @vps_cpu_cores = add_metric(
        :gauge,
        :vps_cpu_cores,
        docstring: 'Number of assigned CPU cores',
        labels: VPS_LABELS
      )

      @vps_cpu_usage_percent = add_metric(
        :gauge,
        :vps_cpu_usage_percent,
        docstring: 'CPU usage in percent',
        labels: VPS_LABELS + %i[mode]
      )

      @vps_transferred = {
        bytes: add_metric(
          :gauge,
          :vps_transferred_bytes,
          docstring: 'Number of transferred bytes over network',
          labels: NETACC_LABELS
        ),

        packets: add_metric(
          :gauge,
          :vps_transferred_packets,
          docstring: 'Number of transferred packets over network',
          labels: NETACC_LABELS
        )
      }

      @vps_features = add_metric(
        :gauge,
        :vps_feature,
        docstring: '1 if the feature is enable, 0 if disabled',
        labels: VPS_LABELS + %i[feature]
      )

      @vps_expiration = add_metric(
        :gauge,
        :vps_expiration_time,
        docstring: 'Time at which the VPS expires',
        labels: VPS_LABELS
      )

      @dataset_properties = DATASET_PROPERTIES.to_h do |prop, metric|
        [
          prop,
          add_metric(
            :gauge,
            :"dataset_#{metric}",
            docstring: "ZFS dataset property #{prop}",
            labels: DATASET_LABELS
          )
        ]
      end

      @incident_reports = add_metric(
        :gauge,
        :incident_report_count,
        docstring: 'Number of incident reports',
        labels: INCIDENT_REPORT_LABELS
      )

      @oom_reports = add_metric(
        :gauge,
        :oom_report_count,
        docstring: 'Number of out-of-memory reports',
        labels: OOM_REPORT_LABELS
      )

      @transaction_chains = add_metric(
        :gauge,
        :transaction_chain_count,
        docstring: 'Numbers of transaction chains',
        labels: %i[state]
      )

      @user_sessions = add_metric(
        :gauge,
        :user_sessions,
        docstring: 'Number of user sessions',
        labels: %i[auth_type state]
      )

      @user_failed_logins = add_metric(
        :gauge,
        :user_failed_logins,
        docstring: 'Number of failed logins to vpsAdmin',
        labels: %i[auth_type]
      )
    end

    def add_metric(type, name, docstring: '', labels: [])
      @registry.send(type, :"#{@token.metric_prefix}#{name}", docstring:, labels:)
    end

    def node_labels(node)
      {
        node_id: node.id,
        node_name: node.domain_name,
        location_id: node.location_id,
        location_label: node.location.label
      }
    end

    def pool_labels(pool)
      node_labels(pool.node).merge(
        pool_id: pool.id,
        pool_name: pool.name
      )
    end

    def vps_labels(vps)
      {
        vps_id: vps.id,
        node_id: vps.node_id,
        node_name: vps.node.domain_name,
        location_id: vps.node.location_id,
        location_label: vps.node.location.label
      }
    end

    def netacc_labels(acc, direction)
      vps_labels(acc.network_interface.vps).merge(
        netif_id: acc.network_interface_id,
        netif_name: acc.network_interface.name,
        year: acc.year,
        month: acc.month,
        direction:
      )
    end

    def dataset_labels(dip)
      node = dip.pool.node
      pool = dip.pool

      {
        node_id: node.id,
        node_name: node.domain_name,
        location_id: node.location_id,
        location_label: node.location.label,
        pool_id: pool.id,
        pool_name: pool.name,
        dataset_id: dip.dataset_id,
        dataset_name: dip.dataset.full_name
      }
    end

    def incident_report_labels(vps:, codename:)
      vps_labels(vps).merge(codename:)
    end

    def oom_report_labels(vps:, invoked_by_name:, killed_name:)
      vps_labels(vps).merge(
        invoked_by_name:,
        killed_name:
      )
    end
  end
end
