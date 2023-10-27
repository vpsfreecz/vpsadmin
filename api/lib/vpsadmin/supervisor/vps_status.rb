module VpsAdmin::Supervisor
  class VpsStatus
    LOG_INTERVAL = 3600

    AVERAGES = %i(loadavg process_count used_memory cpu_idle)

    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(10)

      exchange = @channel.direct('node.vps_statuses')
      queue = @channel.queue('node.vps_statuses')

      queue.bind(exchange)

      queue.subscribe do |_delivery_info, _properties, payload|
        new_status = JSON.parse(payload)

        current_status = ::VpsCurrentStatus.find_or_initialize_by(vps_id: new_status['id'])
        update_status(current_status, new_status)
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
        total_memory: memory,
        total_swap: swap,
        cpus: cpus,
        updated_at: Time.at(new_status['time']),
      )

      if current_status.status && current_status.is_running
        current_status.assign_attributes(
          uptime: new_status['uptime'],
          loadavg: new_status['loadavg'] && new_status['loadavg']['5'],
          process_count: new_status['process_count'],
          used_memory: new_status['used_memory'] / 1024 / 1024,
          cpu_idle: (cpus * 100.0 - new_status['cpu_usage']) / cpus,
        )

        if new_status['hostname']
          ::Vps.where(id: current_status.vps_id).update_all(hostname: new_status['hostname'])
        end
      else
        current_status.assign_attributes(
          uptime: nil,
          loadavg: nil,
          process_count: nil,
          used_memory: nil,
          cpu_idle: nil,
        )
      end

      if current_status.last_log_at.nil? \
         || current_status.status_changed? \
         || current_status.is_running_changed? \
         || current_status.last_log_at + LOG_INTERVAL < now
        # Log status and reset averages
        log_status(current_status)

        current_status.assign_attributes(
          last_log_at: now,
          update_count: 1,
        )

        AVERAGES.each do |attr|
          current_status.assign_attributes(:"sum_#{attr}" => current_status.send(attr))
        end
      else
        # Compute averages
        AVERAGES.each do |attr|
          avg_attr = :"sum_#{attr}"

          if current_status.status && current_status.is_running
            avg_value = current_status.send(avg_attr)
            cur_value = current_status.send(attr)
            new_value = avg_value ? avg_value + cur_value : cur_value

            current_status.assign_attributes(avg_attr => new_value)
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
        uptime: current_status.uptime,
        cpus: current_status.cpus,
        total_memory: current_status.total_memory,
        total_swap: current_status.total_swap,
        created_at: current_status.updated_at,
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

    def find_cluster_resources(vps_id)
      resources = %w(cpu memory swap)
      ret = Array.new(3)

      ::ClusterResourceUse
        .select('cluster_resources.name, cluster_resource_uses.value')
        .joins(user_cluster_resource: [:cluster_resource],)
        .where(
          cluster_resources: {name: resources},
          class_name: ::Vps.name,
          table_name: ::Vps.table_name,
          row_id: vps_id,
        ).each do |ucr|
        ret[ resources.index(ucr.name) ] = ucr.value
      end

      ret
    end
  end
end
