module VpsAdmin::Supervisor
  class DatasetExpansions
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(1)

      exchange = @channel.direct('node.dataset_expansions')
      queue = @channel.queue('node.dataset_expansions', durable: true)

      queue.bind(exchange)

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
        updated_at: t,
      )

      begin
        exp = VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent.run(
          new_event,
          deadline: VpsAdmin::API::Tasks::DatasetExpansion::DEADLINE,
        )
      rescue ::ResourceLocked
        # Save the event to be later processed by the appropriate rake task
        new_event.save!
        return
      end

      if exp && exp.enable_notifications && exp.vps.active?
        TransactionChains::Mail::VpsDatasetExpanded.fire(exp)
      end
    end
  end
end
