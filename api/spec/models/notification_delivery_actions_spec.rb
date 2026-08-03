require_relative '../spec_helper'

RSpec.describe VpsAdmin::API::Notifications::DeliveryActions do
  subject(:registry) { described_class }

  def build_delivery_action(
    name,
    config_section: name,
    template_context_fallbacks: [],
    templates: false
  )
    Class.new(VpsAdmin::API::Notifications::DeliveryActions::Base) do
      action name,
             label: name.to_s,
             queue: "vpsadmin.notifications.#{name}",
             routing_key: "delivery.#{name}",
             config_section: config_section,
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 },
             template_context_fallbacks: template_context_fallbacks,
             templates: templates
      target_kind :custom, label: 'custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end
  end

  def with_isolated_registry
    variables = %i[@classes @instances @finalized]
    state = variables.to_h do |variable|
      [variable, registry.instance_variable_get(variable)]
    end
    registry.instance_variable_set(:@classes, {})
    registry.instance_variable_set(:@instances, {})
    registry.instance_variable_set(:@finalized, false)

    yield
  ensure
    state&.each do |variable, value|
      registry.instance_variable_set(variable, value)
    end
  end

  it 'derives public delivery metadata from registered action classes' do
    expect(registry).to be_finalized
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

  it 'validates duplicated deployment defaults against registered actions' do
    contract = {
      'actions' => registry.names,
      'action_defaults' => registry.deployment_defaults
    }

    expect { registry.validate_deployment_contract!(contract) }.not_to raise_error
    expect do
      registry.validate_deployment_contract!(
        contract.merge('actions' => [*registry.names, 'missing'])
      )
    end.to raise_error(ArgumentError, /unknown notification delivery actions missing/)
    expect do
      registry.validate_deployment_contract!(
        contract.merge(
          'action_defaults' => contract['action_defaults'].merge(
            'email' => contract['action_defaults']['email'].merge('concurrency' => 99)
          )
        )
      )
    end.to raise_error(ArgumentError, /defaults differ from the Ruby registry/)
  end

  it 'allows registered actions without Nix-specific default overrides' do
    contract = {
      'actions' => registry.names,
      'action_defaults' => registry.deployment_defaults.slice('email')
    }

    expect { registry.validate_deployment_contract!(contract) }.not_to raise_error
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

  it 'rejects duplicate config sections without mutating the registry' do
    duplicate_config = build_delivery_action(
      :spec_duplicate_config,
      config_section: :email
    )
    original_names = registry.names
    original_labels = registry.labels

    expect { registry.register(duplicate_config) }
      .to raise_error(ArgumentError, /config section "email" is already registered/)
    expect(registry.names).to eq(original_names)
    expect(registry.labels).to eq(original_labels)
  end

  it 'rejects action names that cannot be used safely by deployment tooling' do
    invalid_name = Class.new(VpsAdmin::API::Notifications::DeliveryActions::Base) do
      action :'invalid/action',
             label: 'Invalid action',
             queue: 'vpsadmin.notifications.invalid-action',
             routing_key: 'delivery.invalid-action',
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 }
      target_kind :custom, label: 'custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end

    expect { registry.register(invalid_name) }
      .to raise_error(ArgumentError, /incomplete notification delivery action/)
  end

  it 'rejects duplicate target kinds within one action declaration' do
    expect do
      Class.new(VpsAdmin::API::Notifications::DeliveryActions::Base) do
        action :spec_duplicate_target_kind,
               label: 'Spec duplicate target kind',
               queue: 'vpsadmin.notifications.spec-duplicate-target-kind',
               routing_key: 'delivery.spec-duplicate-target-kind',
               default_concurrency: 1,
               default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 }
        target_kind :custom, label: 'custom target'
        target_kind :custom, label: 'another custom target'
      end
    end.to raise_error(ArgumentError, /target kind "custom" is already declared/)
  end

  it 'rejects conflicting target kind labels before registering the action' do
    conflicting_target_label = Class.new(
      VpsAdmin::API::Notifications::DeliveryActions::Base
    ) do
      action :spec_conflicting_target_label,
             label: 'Spec conflicting target label',
             queue: 'vpsadmin.notifications.spec-conflicting-target-label',
             routing_key: 'delivery.spec-conflicting-target-label',
             default_concurrency: 1,
             default_rate_limits: { minute: 1, hour: 1, day: 1, week: 1 }
      target_kind :custom, label: 'conflicting custom target'

      def deliver(_delivery)
        VpsAdmin::API::Notifications::DeliveryResult.new
      end
    end
    original_names = registry.names
    original_target_kind_labels = registry.target_kind_labels

    expect { registry.register(conflicting_target_label) }
      .to raise_error(ArgumentError, /conflicting label.*"custom"/)
    expect(registry.names).to eq(original_names)
    expect(registry.target_kind_labels).to eq(original_target_kind_labels)
  end

  it 'rejects template fallbacks on actions which cannot render templates' do
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

    expect { registry.register(non_template_action) }
      .to raise_error(ArgumentError, /incomplete notification delivery action/)
  end

  it 'resolves template fallbacks after all action files have been discovered' do
    with_isolated_registry do
      early_action = build_delivery_action(
        :a_pre_email_action,
        template_context_fallbacks: [:email],
        templates: true
      )

      registry.register(early_action)
      registry.register(VpsAdmin::API::Notifications::DeliveryActions::Email)

      expect(registry.names).to eq(%w[a_pre_email_action email])
      expect { registry.finalize! }.not_to raise_error
      expect(registry).to be_finalized
    end
  end

  it 'rejects unresolved and non-template fallbacks atomically at finalization' do
    with_isolated_registry do
      registry.register(
        build_delivery_action(
          :spec_missing_fallback,
          template_context_fallbacks: [:missing],
          templates: true
        )
      )

      expect { registry.finalize! }
        .to raise_error(ArgumentError, /unknown template context fallback :missing/)
      expect(registry).not_to be_finalized
    end

    with_isolated_registry do
      registry.register(build_delivery_action(:plain_context))
      registry.register(
        build_delivery_action(
          :spec_non_template_context,
          template_context_fallbacks: [:plain_context],
          templates: true
        )
      )

      expect { registry.finalize! }
        .to raise_error(ArgumentError, /non-template context fallback :plain_context/)
      expect(registry).not_to be_finalized
    end

    expect(registry).to be_finalized
  end

  it 'rejects a late unresolved fallback without mutating a finalized registry' do
    unknown_fallback = build_delivery_action(
      :spec_unknown_fallback,
      template_context_fallbacks: [:missing],
      templates: true
    )
    original_names = registry.names

    expect { registry.register(unknown_fallback) }
      .to raise_error(ArgumentError, /unknown template context fallback :missing/)
    expect(registry.names).to eq(original_names)
    expect(registry).to be_finalized
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

  it 'rejects delivery results with an unknown outcome' do
    expect do
      VpsAdmin::API::Notifications::DeliveryResult.new(outcome: :unknown)
    end.to raise_error(ArgumentError, /invalid notification delivery outcome/)
  end

  it 'keeps transport-specific failures compatible with the generic contract' do
    webhook_error = VpsAdmin::API::Notifications::WebhookResponseError.new(
      503,
      'unavailable',
      'retry-after' => ['10']
    )
    telegram_error = VpsAdmin::API::Notifications::TelegramResponseError.new(
      429,
      'limited',
      'Telegram is rate limited'
    )
    sms_error = VpsAdmin::API::Notifications::SmsGatewayResponseError.new(
      502,
      'bad gateway',
      'SMS gateway failed'
    )

    expect([webhook_error, telegram_error, sms_error])
      .to all(be_a(VpsAdmin::API::Notifications::DeliveryFailure))
    expect(webhook_error.response_status).to eq(503)
    expect(webhook_error.response_body).to eq('unavailable')
    expect(webhook_error.response_headers).to eq('retry-after' => ['10'])
    expect(telegram_error.response_headers).to be_nil
    expect(sms_error.response_status).to eq(502)
  end
end
