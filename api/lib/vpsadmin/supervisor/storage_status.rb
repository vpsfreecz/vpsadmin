module VpsAdmin::Supervisor
  class StorageStatus
    LOG_INTERVAL = 3600

    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(10)

      exchange = @channel.direct('node.storage_statuses')
      queue = @channel.queue('node.storage_statuses')

      queue.bind(exchange)

      queue.subscribe do |_delivery_info, _properties, payload|
        status = JSON.parse(payload)
        update_dataset_properties(status)
      end
    end

    protected
    def update_dataset_properties(status)
      now = Time.now
      updated_at = Time.at(status['time'])

      ::DatasetProperty.where(
        id: status['properties'].map { |prop_st| prop_st['id'] },
      ).each do |prop|
        prop_st = status['properties'].detect { |v| v['id'] == prop.id }
        next if prop_st.nil?

        prop.value = save_value(prop, prop_st['value'])
        prop.updated_at = updated_at

        if prop.last_log_at.nil? || prop.last_log_at + LOG_INTERVAL < now
          log_value(prop)
          prop.last_log_at = now
        end

        prop.save!
      end
    end

    def log_value(prop)
      ::DatasetPropertyHistory.create!(
        dataset_property: prop,
        value: prop.value,
        created_at: prop.updated_at,
      )
    end

    def save_value(prop, value)
      case prop.name
      when 'compressratio', 'refcompressratio'
        value
      else
        (value / 1024.0 / 1024).round
      end
    end
  end
end
