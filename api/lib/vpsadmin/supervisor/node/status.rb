require_relative 'base'

module VpsAdmin::Supervisor
  class Node::Status < Node::Base
    LOG_INTERVAL = 900

    AVERAGES = %i[
      process_count
      cpu_user cpu_nice cpu_system cpu_idle cpu_iowait cpu_irq cpu_softirq cpu_guest
      loadavg
      used_memory used_swap
      arc_c_max arc_c arc_size arc_hitpercent
    ]

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
      now = Time.now
      check_time = Time.at(new_status['time'])
      current_status.created_at ||= check_time
      current_status.update_count ||= 1

      current_status.assign_attributes(
        updated_at: check_time,
        uptime: new_status['uptime'],
        process_count: new_status['nproc'],
        loadavg: new_status['loadavg']['5'],
        vpsadmin_version: new_status['vpsadmin_version'],
        kernel: new_status['kernel'],
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

      if new_status['arc']
        current_status.assign_attributes(
          arc_c_max: new_status['arc']['c_max'] / 1024 / 1024,
          arc_c: new_status['arc']['c'] / 1024 / 1024,
          arc_size: new_status['arc']['size'] / 1024 / 1024,
          arc_hitpercent: new_status['arc']['hitpercent']
        )
      else
        current_status.assign_attributes(
          arc_c_max: nil,
          arc_c: nil,
          arc_size: nil,
          arc_hitpercent: nil
        )
      end

      if current_status.last_log_at.nil? || current_status.last_log_at + LOG_INTERVAL < now
        # Log status and reset averages
        log_status(current_status)

        current_status.assign_attributes(
          last_log_at: now,
          update_count: 1
        )

        AVERAGES.each do |attr|
          current_status.assign_attributes("sum_#{attr}": current_status.send(attr))
        end
      else
        # Compute averages
        AVERAGES.each do |attr|
          avg_attr = :"sum_#{attr}"
          avg_value = current_status.send(avg_attr)

          # Not all metrics must be available, e.g. there's no ZFS ARC on mailer
          # nodes.
          next if avg_value.nil?

          cur_value = current_status.send(attr)

          current_status.assign_attributes(avg_attr => avg_value + cur_value)
        end

        current_status.update_count += 1
      end

      begin
        current_status.save!
      rescue ActiveRecord::RecordNotUnique
        # Possible race condition when adding a new node, it is safe to ignore
        # as other status updates will pass.
      end

      nil
    end

    def log_status(current_status)
      update_count = current_status.update_count

      log = ::NodeStatus.new(
        node_id: current_status.node_id,
        uptime: current_status.uptime,
        cpus: current_status.cpus,
        total_memory: current_status.total_memory,
        total_swap: current_status.total_swap,
        vpsadmin_version: current_status.vpsadmin_version,
        kernel: current_status.kernel,
        cgroup_version: current_status.cgroup_version,
        created_at: current_status.updated_at
      )

      AVERAGES.each do |attr|
        sum = current_status.send(:"sum_#{attr}")

        v =
          if sum
            sum / current_status.update_count
          else
            current_status.send(attr)
          end

        log.assign_attributes(attr => v)
      end

      log.save!
    end
  end
end
