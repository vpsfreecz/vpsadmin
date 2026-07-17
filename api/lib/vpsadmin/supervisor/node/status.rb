require_relative 'base'

module VpsAdmin::Supervisor
  class Node::Status < Node::Base
    LOG_INTERVAL = 900
    AVERAGES = %i[
      process_count
      cpu_user cpu_nice cpu_system cpu_idle cpu_iowait cpu_irq cpu_softirq cpu_guest
      loadavg1 loadavg5 loadavg15
      used_memory used_swap
      arc_c_max arc_c arc_size arc_hitpercent
    ].freeze

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('statuses'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'statuses')

      queue.subscribe do |_delivery_info, _properties, payload|
        new_status = JSON.parse(payload)

        next if new_status['id'] != node.id

        current_status = ::NodeCurrentStatus.find_or_initialize_by(node_id: new_status['id'])
        update_status(current_status, new_status)
      end
    end

    protected

    def update_status(current_status, new_status)
      node.with_lock do
        current_status = ::NodeCurrentStatus.find_by(node:) || current_status
        check_time = Time.at(new_status['time'])

        # Supervisor processes may have queued the same Node concurrently. Always
        # compare and replace evidence while holding the Node lock, and never let
        # a delayed report move current status backwards.
        if current_status.persisted? &&
           current_status.updated_at &&
           current_status.updated_at > check_time
          return nil
        end

        update_status_locked(current_status, new_status, check_time)
      end
    rescue ActiveRecord::RecordNotUnique
      # Possible race condition when adding a new node, it is safe to ignore
      # as other status updates will pass.
      nil
    end

    def update_status_locked(current_status, new_status, check_time)
      now = Time.now
      parsed_evidence = if kernel_host? && new_status.has_key?('security_evidence')
                          VpsAdmin::API::KernelEvidence::PayloadParser.call(
                            new_status['security_evidence']
                          )
                        end
      kernel_evidence = parsed_evidence&.report
      record_kernel_evidence = parsed_evidence&.record_events
      kernel_configuration = parsed_evidence&.kernel_configuration
      comparison = VpsAdmin::API::KernelEvidence::SnapshotReader.comparison(
        node:,
        current_snapshot: current_status.kernel_evidence
      )
      previous_kernel_evidence = comparison.report
      previous_kernel_evidence_observed_at = comparison.observed_at
      current_status.created_at ||= check_time
      if current_status.update_count.to_i <= 0
        current_status.update_count = 1
        current_status.last_log_at = nil

        AVERAGES.each do |attr|
          current_status.assign_attributes("sum_#{attr}": nil)
        end
      end

      current_status.assign_attributes(
        updated_at: check_time,
        uptime: new_status['uptime'],
        process_count: new_status['nproc'],
        loadavg1: new_status['loadavg']['1'],
        loadavg5: new_status['loadavg']['5'],
        loadavg15: new_status['loadavg']['15'],
        vpsadmin_version: new_status['vpsadmin_version'],
        kernel: kernel_host? ? new_status['kernel'] : nil,
        cgroup_version: new_status['cgroup_version'],
        cpus: new_status['cpus'],
        cpu_user: new_status['cpu']['user'],
        cpu_nice: new_status['cpu']['nice'],
        cpu_system: new_status['cpu']['system'],
        cpu_idle: new_status['cpu']['idle'],
        cpu_iowait: new_status['cpu']['iowait'],
        cpu_irq: new_status['cpu']['irq'],
        cpu_softirq: new_status['cpu']['softirq'],
        cpu_guest: new_status['cpu']['guest'],
        total_memory: new_status['memory']['total'] / 1024,
        used_memory: new_status['memory']['used'] / 1024,
        total_swap: new_status['swap']['total'] / 1024,
        used_swap: new_status['swap']['used'] / 1024,
        pool_state: new_status['storage']['state'],
        pool_scan: new_status['storage']['scan'],
        pool_scan_percent: new_status['storage']['scan_percent'],
        pool_checked_at: Time.at(new_status['storage']['checked_at'])
      )

      assign_arc(current_status, new_status['arc'])
      update_status_averages(current_status, now)

      ::NodeCurrentStatus.transaction(requires_new: true) do
        store_kernel_configuration!(kernel_configuration) if kernel_configuration
        current_status.save!
        record_system_state!(current_status, check_time) if kernel_host?
        if record_kernel_evidence
          record_evidence_events(
            report: kernel_evidence,
            previous_report: previous_kernel_evidence,
            previous_observed_at: previous_kernel_evidence_observed_at,
            observed_at: check_time,
            received_at: now
          )
        end
        store_current_evidence(current_status, kernel_evidence, check_time, now)

        # Active Record timestamping saves at receipt time. The status
        # timestamp is the Node observation time and our ordering watermark.
        current_status.updated_at = check_time
        current_status.save!(touch: false)
      end

      nil
    end

    def assign_arc(current_status, arc)
      if arc
        current_status.assign_attributes(
          arc_c_max: arc['c_max'] / 1024 / 1024,
          arc_c: arc['c'] / 1024 / 1024,
          arc_size: arc['size'] / 1024 / 1024,
          arc_hitpercent: arc['hitpercent']
        )
      else
        current_status.assign_attributes(
          arc_c_max: nil,
          arc_c: nil,
          arc_size: nil,
          arc_hitpercent: nil
        )
      end
    end

    def update_status_averages(current_status, now)
      if current_status.last_log_at.nil? || current_status.last_log_at + LOG_INTERVAL < now
        log_status(current_status)
        current_status.assign_attributes(last_log_at: now, update_count: 1)
        AVERAGES.each do |attr|
          current_status.assign_attributes("sum_#{attr}": current_status.send(attr))
        end
        return
      end

      AVERAGES.each do |attr|
        average_attribute = :"sum_#{attr}"
        average_value = current_status.send(average_attribute)
        next if average_value.nil?

        current_value = current_status.send(attr)
        if current_value.nil?
          current_status.assign_attributes(average_attribute => nil)
          next
        end

        current_status.assign_attributes(average_attribute => average_value + current_value)
      end
      current_status.update_count += 1
    end

    def record_evidence_events(
      report:,
      previous_report:,
      previous_observed_at:,
      observed_at:,
      received_at:
    )
      VpsAdmin::API::Operations::Node::RecordKernelEvidence.run(
        node:,
        observed_at:,
        received_at:,
        report:,
        previous_report:,
        previous_observed_at:
      )
    end

    def store_current_evidence(current_status, report, observed_at, received_at)
      if report
        snapshot = current_status.kernel_evidence || ::NodeKernelEvidence.new(
          node:,
          snapshot_type: :current
        )
        VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
          snapshot:,
          report:,
          observed_at:,
          received_at:
        )
        current_status.update!(kernel_evidence: snapshot) \
          unless current_status.node_kernel_evidence_id == snapshot.id
      elsif !kernel_host? && current_status.kernel_evidence
        snapshot = current_status.kernel_evidence
        current_status.update!(kernel_evidence: nil)
        snapshot.destroy!
      end
    end

    def record_system_state!(current_status, observed_at)
      values = VpsAdmin::API::SystemState::Normalizer.from_status(current_status)
      VpsAdmin::API::SystemState::Recorder.call(node:, values:, observed_at:)

      cache_values = values.slice(:cpus, :total_memory, :total_swap)
                           .transform_values { |value| value || 0 }
      node.update_columns(cache_values)
    end

    def store_kernel_configuration!(attributes)
      VpsAdmin::API::KernelEvidence::ConfigurationWriter.call(**attributes)
    end

    def kernel_host? = node.node? || node.storage?

    def log_status(current_status)
      log = ::NodeStatus.new(
        node_id: current_status.node_id,
        uptime: current_status.uptime,
        cpus: current_status.cpus,
        total_memory: current_status.total_memory,
        total_swap: current_status.total_swap,
        vpsadmin_version: current_status.vpsadmin_version,
        kernel: current_status.kernel || '',
        cgroup_version: current_status.cgroup_version,
        created_at: current_status.updated_at
      )

      AVERAGES.each do |attr|
        sum = current_status.send(:"sum_#{attr}")
        value = sum ? sum / current_status.update_count : current_status.send(attr)
        log.assign_attributes(attr => value)
      end

      log.save!
    end
  end
end
