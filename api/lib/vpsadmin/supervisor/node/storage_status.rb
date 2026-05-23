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
    LOG_PROPERTIES = %w[used referenced available].freeze

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('storage_statuses'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
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
      vps_sums = {}
      properties = status['properties']
      dataset_properties =
        ::DatasetProperty
        .joins(dataset_in_pool: :pool)
        .includes(:dataset)
        .where(
          id: properties.map { |prop| prop['id'] },
          pools: { node_id: node.id }
        )
        .index_by(&:id)
      vpses =
        ::Vps
        .includes(:dataset)
        .where(
          id: properties.filter_map { |prop| prop['vps_id'] },
          node_id: node.id
        )
        .index_by(&:id)

      properties.each do |prop|
        dataset_property = dataset_properties[prop['id']]
        next if dataset_property.nil?

        value = save_value(prop['name'], prop['value'])

        ::DatasetProperty.where(id: dataset_property.id).update_all(
          value:,
          updated_at:
        )

        # nodectld must ensure that datasets of one VPS are in a single batch
        # and not spread out over two or more batches. As batches are processed
        # independently, the VPS sums would be incorrect.
        if %w[refquota referenced].include?(prop['name']) && (vps_id = prop['vps_id'])
          vps = vpses[vps_id]
          next if vps.nil? || !dataset_property_belongs_to_vps?(dataset_property, vps)

          vps_sums[vps_id] ||= { 'refquota' => 0, 'referenced' => 0 }
          vps_sums[vps_id][prop['name']] += value
        end

        next unless save_log && LOG_PROPERTIES.include?(prop['name'])

        ::DatasetPropertyHistory.create!(
          dataset_property_id: dataset_property.id,
          value:,
          created_at: updated_at
        )
      end

      vps_sums.each do |vps_id, sums|
        ::VpsCurrentStatus.where(vps_id:).update_all(
          total_diskspace: sums['refquota'],
          used_diskspace: sums['referenced']
        )
      end
    end

    def dataset_property_belongs_to_vps?(dataset_property, vps)
      property_dataset = dataset_property.dataset
      vps_dataset = vps.dataset

      return false if property_dataset.nil? || vps_dataset.nil?

      property_dataset.id == vps_dataset.id ||
        property_dataset.ancestor_ids.include?(vps_dataset.id)
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
