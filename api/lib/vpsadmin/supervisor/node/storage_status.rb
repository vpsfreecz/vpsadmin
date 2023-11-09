require_relative 'base'

module VpsAdmin::Supervisor
  class Node::StorageStatus < Node::Base
    # Each update carries per-node ever-incrementing message id. This id is the
    # same for one update spread over multiple messages. This constant determines
    # how often are property values logged. For example, when nodectld sends
    # status update very 90 seconds, logging every 40th message (3600 / 90) will
    # log values once an hour.
    #
    # Note that the id counter is reset on nodectld restart.
    LOG_NTH_MESSAGE = 40

    # TODO: add compressratio and refcompressratio: these values are floats while
    # {DatasetPropertyHistory} can store only integers.
    LOG_PROPERTIES = %w(used referenced available)

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('storage_statuses'),
        durable: true,
        arguments: {'x-queue-type' => 'quorum'},
      )

      queue.bind(exchange, routing_key: 'storage_statuses')

      queue.subscribe do |_delivery_info, _properties, payload|
        status = JSON.parse(payload)
        update_dataset_properties(status)
      end
    end

    protected
    def update_dataset_properties(status)
      now = Time.now
      updated_at = Time.at(status['time'])
      save_log = status['message_id'] % LOG_NTH_MESSAGE == 0

      status['properties'].each do |prop|
        value = save_value(prop['name'], prop['value'])

        ::DatasetProperty.where(id: prop['id']).update_all(
          value: value,
          updated_at: updated_at,
        )

        if save_log && LOG_PROPERTIES.include?(prop['name'])
          ::DatasetPropertyHistory.create!(
            dataset_property_id: prop['id'],
            value: value,
            created_at: updated_at,
          )
        end
      end
    end

    def save_value(name, value)
      case name
      when 'compressratio', 'refcompressratio'
        value
      else
        (value / 1024.0 / 1024).round
      end
    end
  end
end
