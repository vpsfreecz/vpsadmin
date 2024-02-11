require_relative 'base'

module VpsAdmin::Supervisor
  class Node::DatasetExpansions < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('dataset_expansions'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'dataset_expansions')

      queue.subscribe(manual_ack: true) do |delivery_info, _properties, payload|
        event = JSON.parse(payload)
        process_event(event)
        @channel.ack(delivery_info.delivery_tag)
      end
    end

    protected

    def process_event(event)
      t = Time.at(event['time'])

      new_event = ::DatasetExpansionEvent.new(
        dataset_id: event['dataset_id'],
        original_refquota: event['original_refquota'],
        new_refquota: event['new_refquota'],
        added_space: event['added_space'],
        created_at: t,
        updated_at: t
      )

      # Check if we're authorized to handle expansions from this node
      return if new_event.dataset.primary_dataset_in_pool!.pool.node_id != node.id

      begin
        exp = VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent.run(
          new_event,
          max_over_refquota_seconds: VpsAdmin::API::Tasks::DatasetExpansion::MAX_OVER_REFQUOTA_SECONDS
        )
      rescue ::ResourceLocked
        # Save the event to be later processed by the appropriate rake task
        new_event.save!
        return
      end

      return unless exp && exp.enable_notifications && exp.vps.active?

      TransactionChains::Mail::VpsDatasetExpanded.fire(exp)
    end
  end
end
