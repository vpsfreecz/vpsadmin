require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsStatus < Node::Base
    LOG_INTERVAL = 3600

    AVERAGES = %i[loadavg1 loadavg5 loadavg15 process_count used_memory used_diskspace cpu_idle].freeze

    def self.setup(channel)
      channel.prefetch(5)
    end

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('vps_statuses'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'vps_statuses')

      queue.subscribe do |_delivery_info, _properties, payload|
        new_status = JSON.parse(payload)

        current_status = ::VpsCurrentStatus.find_or_initialize_by(vps_id: new_status['id'])

        update_status(current_status, new_status) if current_status.vps.node_id == node.id
      end
    end

    protected

    def update_status(current_status, new_status)
      now = Time.now

      current_status.update_count ||= 1

      cpus, memory, swap = find_cluster_resources(current_status.vps_id)

      current_status.assign_attributes(
        status: new_status['status'],
        is_running: new_status['running'],
        in_rescue_mode: new_status['in_rescue_mode'],
        qemu_guest_agent: current_status.vps.container? ? false : new_status.fetch('qemu_guest_agent', false),
        total_memory: memory,
        total_swap: swap,
        cpus:,
        updated_at: Time.at(new_status['time'])
      )

      if current_status.status && current_status.is_running
        current_status.assign_attributes(
          uptime: new_status['uptime'],
          loadavg1: new_status['loadavg'] && new_status['loadavg']['1'],
          loadavg5: new_status['loadavg'] && new_status['loadavg']['5'],
          loadavg15: new_status['loadavg'] && new_status['loadavg']['15'],
          process_count: new_status['process_count'],
          used_memory: new_status['used_memory'] / 1024 / 1024,
          cpu_idle: ((cpus * 100.0) - new_status['cpu_usage']) / cpus
        )

        ::Vps.where(id: current_status.vps_id).update_all(hostname: new_status['hostname']) if new_status['hostname']

        if new_status['io_stats']
          update_io_stats(current_status, new_status['io_stats'])
        end

        if new_status['process_states']
          update_os_processes(current_status, new_status['process_states'])
        end
      else
        current_status.assign_attributes(
          uptime: nil,
          loadavg1: nil,
          loadavg5: nil,
          loadavg15: nil,
          process_count: nil,
          used_memory: nil,
          cpu_idle: nil
        )
      end

      if current_status.status && !current_status.is_running && current_status.halted
        current_status.halted = false

        if current_status.vps.autostart_enable
          begin
            TransactionChains::Vps::Autostart.fire2(
              args: [current_status.vps],
              kwargs: { enable: false }
            )
          rescue ResourceLocked
            # ignore
          end
        end
      end

      if current_status.last_log_at.nil? \
         || current_status.status_changed? \
         || current_status.is_running_changed? \
         || current_status.last_log_at + LOG_INTERVAL < now
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

          if current_status.status && current_status.is_running
            avg_value = current_status.send(avg_attr)
            cur_value = current_status.send(attr)

            if cur_value # loadavg can be nil
              new_value = avg_value ? avg_value + cur_value : cur_value

              current_status.assign_attributes(avg_attr => new_value)
            end
          else
            current_status.assign_attributes(avg_attr => nil)
          end
        end

        if current_status.status && current_status.is_running
          current_status.update_count += 1
        else
          current_status.update_count = 1
        end
      end

      begin
        current_status.save!
      rescue ActiveRecord::RecordNotUnique
        # Possible race condition when adding a new VPS
      end

      nil
    end

    def log_status(current_status)
      update_count = current_status.update_count

      log = ::VpsStatus.new(
        vps_id: current_status.vps_id,
        status: current_status.status,
        is_running: current_status.is_running,
        in_rescue_mode: current_status.in_rescue_mode,
        qemu_guest_agent: current_status.qemu_guest_agent,
        uptime: current_status.uptime,
        cpus: current_status.cpus,
        total_memory: current_status.total_memory,
        total_swap: current_status.total_swap,
        total_diskspace: current_status.total_diskspace,
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

    def update_io_stats(current_status, io_stats)
      all_index = io_stats.index { |v| v['storage_volume_id'] == 'all' }
      all = io_stats.delete_at(all_index) if all_index

      ::VpsIoStat.upsert_all(
        io_stats.map do |vol_stats|
          {
            vps_id: current_status.vps_id,
            storage_volume_id: vol_stats['id'],
            read_requests: vol_stats['read_requests'],
            read_bytes: vol_stats['read_bytes'],
            write_requests: vol_stats['write_requests'],
            write_bytes: vol_stats['write_bytes'],
            delta: vol_stats['delta'],
            read_requests_readout: vol_stats['read_requests_readout'],
            read_bytes_readout: vol_stats['read_bytes_readout'],
            write_requests_readout: vol_stats['write_requests_readout'],
            write_bytes_readout: vol_stats['write_bytes_readout']
          }
        end
      )
      io_stats
    end

    def update_os_processes(current_status, os_processes)
      ::VpsOsProcess.upsert_all(
        os_processes.map do |state, count|
          {
            vps_id: current_status.vps_id,
            state:,
            count:,
            created_at: current_status.updated_at,
            updated_at: current_status.updated_at
          }
        end,
        update_only: %i[count]
      )
    end

    def find_cluster_resources(vps_id)
      resources = %w[cpu memory swap]
      ret = Array.new(3)

      ::ClusterResourceUse
        .select('cluster_resources.name, cluster_resource_uses.value')
        .joins(user_cluster_resource: [:cluster_resource])
        .where(
          cluster_resources: { name: resources },
          class_name: ::Vps.name,
          table_name: ::Vps.table_name,
          row_id: vps_id
        ).each do |ucr|
        ret[resources.index(ucr.name)] = ucr.value
      end

      ret
    end
  end
end
