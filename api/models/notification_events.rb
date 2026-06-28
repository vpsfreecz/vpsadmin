module VpsAdmin::API
  module NotificationEvents
    class NonEventTransaction < StandardError; end

    HANDLED_STATES = %w[
      canceled
      prepared
      released
      sending
      sent
      skipped
    ].freeze

    module_function

    def emit!(event_type, **)
      VpsAdmin::API::Events.emit!(event_type, **, release: true)
    end

    def run_chain(chain_class, args: [], kwargs: {}, method: :link_chain)
      ::ApplicationRecord.transaction do
        chain = direct_chain(chain_class)
        chain.public_send(method, *Array(args), **kwargs)
      end
    end

    def ensure_no_failed_email!(event, message:)
      return if event.nil?

      failed = event
               .event_deliveries
               .where(action: 'email', state: 'failed')
               .order(:id)
               .first
      return unless failed

      raise "#{message}: #{failed.error_summary}"
    end

    def ensure_email_handled!(event, message:)
      raise "#{message}: no delivery was prepared" if event.nil?

      deliveries = event.event_deliveries.reload.select(&:email_action?)
      return if deliveries.any? { |delivery| HANDLED_STATES.include?(delivery.state) }

      failed = deliveries.find(&:failed_state?) || deliveries.first
      detail = failed&.error_summary.presence || 'no delivery was prepared'
      raise "#{message}: #{detail}"
    end

    def direct_chain(chain_class)
      chain_class.new.tap { |chain| prepare_direct_chain(chain) }
    end

    def prepare_direct_chain(chain)
      chain.define_singleton_method(:route_event!) do |event_type, **opts|
        VpsAdmin::API::NotificationEvents.emit!(event_type, **opts)
      end

      chain.define_singleton_method(:prepare_event!) do |event_type, **opts|
        VpsAdmin::API::NotificationEvents.emit!(event_type, **opts)
      end

      chain.define_singleton_method(:release_event_deliveries!) do |_event|
        nil
      end

      chain.define_singleton_method(:concerns) do |_type, *_objects|
        nil
      end

      chain.define_singleton_method(:use_chain) do |nested_chain, opts = {}|
        args = opts[:args] || []
        kwargs = opts[:kwargs] || {}
        VpsAdmin::API::NotificationEvents.run_chain(
          nested_chain,
          args: args.is_a?(Array) ? args : [args],
          kwargs:,
          method: opts[:method] || :link_chain
        )
      end

      %i[append append_t append_to append_or_noop_t mail mail_custom lock].each do |method_name|
        chain.define_singleton_method(method_name) do |*args, **_kwargs|
          detail = args.first.respond_to?(:name) ? args.first.name : args.first.inspect
          raise VpsAdmin::API::NotificationEvents::NonEventTransaction,
                "#{self.class.name} attempted to use #{method_name}(#{detail})"
        end
      end
    end
  end
end
