require_relative '../spec_helper'

RSpec.describe VpsAdmin::API::Notifications::DeliveryActions do
  subject(:registry) { described_class }

  it 'derives public delivery metadata from registered action classes' do
    expect(registry.names).to contain_exactly('email', 'webhook', 'telegram', 'sms')
    expect(registry.labels).to eq(
      'email' => 'E-mail',
      'webhook' => 'Webhook',
      'telegram' => 'Telegram',
      'sms' => 'SMS'
    )
    expect(registry.names.map { |name| registry.queue_name(name) }.uniq.length).to eq(4)
    expect(registry.names.map { |name| registry.routing_key(name) }.uniq.length).to eq(4)
    expect(registry.default_rate_limits.keys).to match_array(registry.names)
    expect(registry.default_rate_limits.values.map(&:keys).uniq)
      .to eq([VpsAdmin::API::Notifications::RateLimits.periods])
  end

  it 'exposes one explicit contract for model, routing, preparation, and transport behavior' do
    expected_methods = %i[
      available?
      validate_target
      normalize_target_value
      identity_key
      display_target
      receiver_action_available?
      plan_delivery
      direct_delivery_plans
      prepared?
      prepare_delivery
      deliver
      select_due_deliveries
      throttle_delay
      template_context_actions
    ]

    registry.names.each do |name|
      action = registry.fetch(name)
      expect(expected_methods - action.public_methods).to be_empty
    end
  end

  it 'keeps direct delivery planning behind action implementations' do
    email = registry.fetch('email')

    expect(email.method(:direct_delivery_plans).owner)
      .to eq(VpsAdmin::API::Notifications::DeliveryActions::Email)
    expect(registry.fetch('webhook').method(:direct_delivery_plans).owner)
      .to eq(VpsAdmin::API::Notifications::DeliveryActions::Base)
  end

  it 'rejects duplicate names, queues, and routing keys instead of replacing actions' do
    expect { registry.register(VpsAdmin::API::Notifications::DeliveryActions::Email) }
      .to raise_error(ArgumentError, /already registered/)

    duplicate_queue = Class.new(VpsAdmin::API::Notifications::DeliveryActions::Base) do
      action :spec_duplicate_queue,
             label: 'Spec duplicate queue',
             queue: 'vpsadmin.notifications.email',
             routing_key: 'delivery.spec-duplicate-queue',
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 }
      target_kind :custom, label: 'custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end

    expect { registry.register(duplicate_queue) }
      .to raise_error(ArgumentError, /queue .* already registered/)

    duplicate_key = Class.new(VpsAdmin::API::Notifications::DeliveryActions::Base) do
      action :spec_duplicate_key,
             label: 'Spec duplicate key',
             queue: 'vpsadmin.notifications.spec-duplicate-key',
             routing_key: 'delivery.email',
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 }
      target_kind :custom, label: 'custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end

    expect { registry.register(duplicate_key) }
      .to raise_error(ArgumentError, /routing key .* already registered/)
  end

  it 'rejects invalid template fallback metadata' do
    non_template_action = Class.new(
      VpsAdmin::API::Notifications::DeliveryActions::Base
    ) do
      action :spec_non_template_fallback,
             label: 'Spec non-template fallback',
             queue: 'vpsadmin.notifications.spec-non-template-fallback',
             routing_key: 'delivery.spec-non-template-fallback',
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 },
             template_context_fallbacks: [:email]
      target_kind :custom, label: 'custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end

    unknown_fallback = Class.new(
      VpsAdmin::API::Notifications::DeliveryActions::Base
    ) do
      action :spec_unknown_fallback,
             label: 'Spec unknown fallback',
             queue: 'vpsadmin.notifications.spec-unknown-fallback',
             routing_key: 'delivery.spec-unknown-fallback',
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 },
             template_context_fallbacks: [:missing],
             templates: true
      target_kind :custom, label: 'custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end

    expect { registry.register(non_template_action) }
      .to raise_error(ArgumentError, /incomplete notification delivery action/)
    expect { registry.register(unknown_fallback) }
      .to raise_error(ArgumentError, /incomplete notification delivery action/)
  end

  it 'returns an immutable typed transport result' do
    result = VpsAdmin::API::Notifications::DeliveryResult.new(
      outcome: :accepted,
      provider_message_id: 'provider-1',
      response_status: 202
    )

    expect(result).to be_accepted
    expect(result.provider_message_id).to eq('provider-1')
    expect { result.response_status = 200 }.to raise_error(NoMethodError)
  end
end
