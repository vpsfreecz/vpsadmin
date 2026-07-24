require 'digest'

class AddEvents < ActiveRecord::Migration[8.1]
  ADVANCED_NOTIFICATION_TEMPLATE_ROUTE_POSITION = 10
  ADVANCED_EMAIL_ROLE_ROUTE_POSITION = 1_000
  REQUEST_TEMPLATE_TYPES = %w[registration change].freeze
  REQUEST_TEMPLATE_AUDIENCES = %w[user admin].freeze
  REQUEST_TEMPLATE_RESOLVE_STATES = %w[approved denied ignored pending_correction awaiting].freeze
  REQUEST_ADVANCED_EVENT_TEMPLATES = begin
    ret = []

    %w[create update].each do |action|
      event_type = action == 'create' ? 'request.created' : 'request.updated'

      REQUEST_TEMPLATE_AUDIENCES.each do |audience|
        REQUEST_TEMPLATE_TYPES.each do |type|
          template_name = "request_#{action}_#{audience}_#{type}"
          ret << {
            event_type:,
            template_name:,
            legacy_template_names: [template_name],
            label: "Request #{action} #{audience} #{type}",
            roles: [],
            priority: 10,
            matchers: [
              ['request_type', '==', type]
            ]
          }
        end

        template_name = "request_#{action}_#{audience}"
        ret << {
          event_type:,
          template_name:,
          legacy_template_names: [template_name],
          label: "Request #{action} #{audience}",
          roles: [],
          priority: 30,
          matchers: []
        }
      end
    end

    REQUEST_TEMPLATE_AUDIENCES.each do |audience|
      REQUEST_TEMPLATE_TYPES.each do |type|
        REQUEST_TEMPLATE_RESOLVE_STATES.each do |state|
          template_name = "request_resolve_#{audience}_#{type}_#{state}"
          ret << {
            event_type: 'request.resolved',
            template_name:,
            legacy_template_names: [template_name],
            label: "Request resolve #{audience} #{type} #{state}",
            roles: [],
            priority: 0,
            matchers: [
              ['request_type', '==', type],
              ['request_state', '==', state]
            ]
          }
        end

        template_name = "request_resolve_#{audience}_#{type}"
        ret << {
          event_type: 'request.resolved',
          template_name:,
          legacy_template_names: [template_name],
          label: "Request resolve #{audience} #{type}",
          roles: [],
          priority: 10,
          matchers: [
            ['request_type', '==', type]
          ]
        }
      end

      REQUEST_TEMPLATE_RESOLVE_STATES.each do |state|
        template_name = "request_resolve_#{audience}_#{state}"
        ret << {
          event_type: 'request.resolved',
          template_name:,
          legacy_template_names: [template_name],
          label: "Request resolve #{audience} #{state}",
          roles: [],
          priority: 20,
          matchers: [
            ['request_state', '==', state]
          ]
        }
      end

      template_name = "request_resolve_#{audience}"
      ret << {
        event_type: 'request.resolved',
        template_name:,
        legacy_template_names: [template_name],
        label: "Request resolve #{audience}",
        roles: [],
        priority: 30,
        matchers: []
      }
    end

    ret
  end.freeze
  ADVANCED_NOTIFICATION_EVENT_TEMPLATES = [
    {
      event_type: 'user.created',
      template_name: 'user_create',
      label: 'User account created',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'user.suspended',
      template_name: 'user_suspend',
      label: 'User account suspended',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'user.soft_deleted',
      template_name: 'user_soft_delete',
      label: 'User account disabled',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'user.resumed',
      template_name: 'user_resume',
      label: 'User account resumed',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'user.revived',
      template_name: 'user_revive',
      label: 'User account restored',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'user.new_login',
      template_name: 'user_new_login',
      label: 'New sign-in',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'user.new_token',
      template_name: 'user_new_token',
      label: 'New access token',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'user.totp_recovery_code_used',
      template_name: 'user_totp_recovery_code_used',
      label: 'TOTP recovery code used',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'user.failed_logins',
      template_name: 'user_failed_logins',
      label: 'Failed sign-in report',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning',
      legacy_template_names: %w[expiration_user_active],
      label: 'User expiration warning',
      roles: %w[account],
      matchers: [
        ['object', '==', 'user'],
        ['state', '==', 'active']
      ]
    },
    {
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning',
      legacy_template_names: %w[expiration_vps_active],
      label: 'VPS expiration warning',
      roles: %w[account],
      matchers: [
        ['object', '==', 'vps'],
        ['state', '==', 'active']
      ]
    },
    {
      event_type: 'payment.accepted',
      template_name: 'payment_accepted',
      label: 'Payment accepted',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'outage.announced',
      template_name: 'outage_report_user_announce',
      legacy_template_names: %w[outage_report_user_announce],
      label: 'Outage announced',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'outage.updated',
      template_name: 'outage_report_user_update',
      legacy_template_names: %w[outage_report_user_update],
      label: 'Outage updated',
      roles: %w[account],
      matchers: []
    },
    {
      event_type: 'security_advisory.announced',
      template_name: 'security_advisory_user_announce',
      label: 'Security advisory announced',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'security_advisory.updated',
      template_name: 'security_advisory_user_update',
      label: 'Security advisory updated',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.incident_report',
      template_name: 'vps_incident_report',
      label: 'Incident report',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.oom_report',
      template_name: 'vps_oom_report',
      label: 'OOM report',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.oom_prevention',
      template_name: 'vps_oom_prevention',
      label: 'OOM prevention',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.suspended',
      template_name: 'vps_suspend',
      label: 'VPS suspended',
      roles: %w[account admin],
      matchers: []
    },
    {
      event_type: 'vps.resumed',
      template_name: 'vps_resume',
      label: 'VPS resumed',
      roles: %w[account admin],
      matchers: []
    },
    {
      event_type: 'vps.resources_changed',
      template_name: 'vps_resources_change',
      label: 'VPS resources changed',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.dns_resolver_changed',
      template_name: 'vps_dns_resolver_change',
      label: 'VPS DNS resolver changed',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.network_disabled',
      template_name: 'vps_network_disabled',
      label: 'VPS network disabled',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.network_enabled',
      template_name: 'vps_network_enabled',
      label: 'VPS network enabled',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.stopped_over_quota',
      template_name: 'vps_stopped_over_quota',
      label: 'VPS stopped over quota',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.dataset_expanded',
      template_name: 'vps_dataset_expanded',
      label: 'VPS dataset expanded',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.dataset_shrunk',
      template_name: 'vps_dataset_shrunk',
      label: 'VPS dataset shrunk',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'snapshot.download_ready',
      template_name: 'snapshot_download_ready',
      label: 'Snapshot download ready',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'dataset.migration_begun',
      template_name: 'dataset_migration_begun',
      label: 'Dataset migration begun',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'dataset.migration_finished',
      template_name: 'dataset_migration_finished',
      label: 'Dataset migration finished',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.migration_planned',
      template_name: 'vps_migration_planned',
      label: 'VPS migration planned',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.migration_begun',
      template_name: 'vps_migration_begun',
      label: 'VPS migration begun',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.migration_finished',
      template_name: 'vps_migration_finished',
      label: 'VPS migration finished',
      roles: %w[admin],
      matchers: []
    },
    {
      event_type: 'vps.replaced',
      template_name: 'vps_replaced',
      label: 'VPS replaced',
      roles: %w[admin],
      matchers: []
    }
  ].concat(REQUEST_ADVANCED_EVENT_TEMPLATES).freeze
  ADVANCED_EMAIL_ROLE_LABELS = {
    'account' => 'Account management',
    'admin' => 'System administrator'
  }.freeze

  def up
    create_table :notification_receivers do |t|
      t.references  :user,                     null: false
      t.string      :label,                    null: false, limit: 255
      t.text        :description,              null: true
      t.boolean     :enabled,                  null: false, default: true
      t.boolean     :mute,                     null: false, default: false
      t.timestamps                             null: false
    end

    add_index :notification_receivers, %i[user_id enabled],
              name: 'index_notification_receivers_on_user_enabled'
    add_index :notification_receivers, %i[user_id mute],
              name: 'index_notification_receivers_on_user_mute'

    create_table :notification_targets do |t|
      t.references  :user,                     null: false
      t.string      :action,                   null: false, limit: 50
      t.string      :label,                    null: true, limit: 255
      t.integer     :target_kind,              null: false, default: 0
      t.text        :target_value,             null: true
      t.string      :identity_key,             null: true, limit: 255
      t.text        :config,                   null: true
      t.text        :secret,                   null: true
      t.string      :verification_token,       null: true, limit: 255
      t.datetime    :verified_at,              null: true
      t.boolean     :enabled,                  null: false, default: true
      t.text        :last_error,               null: true
      t.timestamps                             null: false
    end

    add_index :notification_targets, %i[user_id action enabled],
              name: 'idx_notification_targets_on_user_action_enabled'
    add_index :notification_targets, %i[user_id action identity_key],
              unique: true,
              name: 'idx_notification_targets_on_user_action_identity'
    add_index :notification_targets, :verification_token, unique: true

    create_table :notification_receiver_targets do |t|
      t.references  :notification_receiver,    null: false,
                                               index: { name: 'idx_receiver_targets_on_receiver' }
      t.references  :notification_target,      null: false,
                                               index: { name: 'idx_receiver_targets_on_target' }
      t.integer     :position,                 null: false, default: 0
      t.timestamps                             null: false
    end

    add_index :notification_receiver_targets, %i[notification_receiver_id notification_target_id],
              unique: true,
              name: 'idx_receiver_targets_on_receiver_target'

    create_table :event_routes do |t|
      t.references  :user,                     null: false
      t.bigint      :parent_id,                null: true
      t.bigint      :notification_receiver_id, null: true
      t.string      :label,                    null: true, limit: 255
      t.integer     :position,                 null: false, default: 0
      t.boolean     :enabled,                  null: false, default: true
      t.string      :event_type,               null: true, limit: 100
      t.string      :event_type_pattern,       null: true, limit: 100
      t.string      :template_name, null: true, limit: 100
      t.boolean     :grouping_enabled,         null: false, default: false
      t.text        :group_by,                 null: true
      t.integer     :group_wait_seconds,       null: true
      t.integer     :group_interval_seconds,   null: true
      t.boolean     :continue,                 null: false, default: false
      t.boolean     :single_use,               null: false, default: false
      t.datetime    :spent_at,                 null: true
      t.datetime    :expires_at,               null: true
      t.bigint      :hit_count,                null: false, default: 0
      t.timestamps                             null: false
    end

    add_index :event_routes, %i[user_id parent_id position id],
              name: 'index_event_routes_on_user_parent_position'
    add_index :event_routes, :enabled
    add_index :event_routes, :event_type
    add_index :event_routes, :parent_id
    add_index :event_routes, :notification_receiver_id
    add_index :event_routes, %i[user_id single_use spent_at],
              name: 'index_event_routes_on_user_single_use_spent'
    add_index :event_routes, :expires_at

    create_table :event_route_matchers do |t|
      t.references  :event_route,              null: false
      t.string      :field,                    null: false, limit: 100
      t.string      :operator,                 null: false, limit: 50
      t.text        :value,                    null: false
      t.timestamps                             null: false
    end

    create_table :events do |t|
      t.references  :user,                     null: true
      t.string      :event_type,               null: false, limit: 100
      t.string      :category,                 null: false, limit: 100
      t.integer     :severity,                 null: false
      t.string      :subject,                  null: false, limit: 255
      t.text        :summary,                  null: true
      t.text        :parameters,               null: true
      t.string      :source_class,             null: true, limit: 100
      t.bigint      :source_id,                null: true
      t.references  :vps,                      null: true
      t.string      :ip_addr,                  null: true, limit: 46
      t.integer     :routing_state,            null: false, default: 0
      t.bigint      :matched_event_route_id,   null: true
      t.timestamps                             null: false
    end

    add_index :events, :event_type
    add_index :events, :category
    add_index :events, :severity
    add_index :events, :routing_state
    add_index :events, :created_at
    add_index :events, :matched_event_route_id

    create_table :event_deliveries do |t|
      t.references  :event,                    null: false
      t.references  :event_route,              null: true
      t.references  :notification_receiver,    null: true
      t.references  :notification_target,      null: true,
                                               index: { name: 'idx_event_deliveries_on_target' }
      t.references  :notification_receiver_target, null: true,
                                                   index: { name: 'idx_event_deliveries_on_receiver_target' }
      t.string      :action,                   null: false, limit: 50
      t.integer     :target_kind,              null: false
      t.text        :target_value,             null: true
      t.string      :target_label,             null: true, limit: 255
      t.text        :target_secret,            null: true
      t.string      :template_name,            null: true, limit: 100
      t.integer     :state,                    null: false
      t.references  :event_delivery_group,     null: true,
                                               index: { name: 'idx_event_deliveries_on_group' }
      t.bigint      :effective_event_delivery_id, null: true
      t.string      :group_key,                null: true, limit: 64
      t.text        :group_labels,             null: true
      t.integer     :group_wait_seconds,       null: true
      t.integer     :group_interval_seconds,   null: true
      t.integer     :mail_log_id,              null: true
      t.integer     :transaction_id,           null: true
      t.datetime    :released_at,              null: true
      t.text        :payload,                  null: true, limit: 4_294_967_295
      t.integer     :attempt_count,            null: false, default: 0
      t.datetime    :next_attempt_at,          null: true
      t.datetime    :last_attempt_at,          null: true
      t.string      :provider_message_id,      null: true, limit: 255
      t.integer     :response_status,          null: true
      t.text        :response_body,            null: true
      t.text        :response_headers,         null: true
      t.text        :error_summary,            null: true
      t.timestamps                             null: false
    end

    add_index :event_deliveries, %i[event_id action state]
    add_index :event_deliveries, %i[action state next_attempt_at],
              name: 'idx_event_deliveries_on_action_state_next_attempt'
    add_index :event_deliveries, :state
    add_index :event_deliveries, :next_attempt_at
    add_index :event_deliveries, :mail_log_id
    add_index :event_deliveries, :transaction_id
    add_index :event_deliveries, :released_at
    add_index :event_deliveries, :effective_event_delivery_id,
              name: 'idx_event_deliveries_on_effective'

    create_table :event_delivery_groups do |t|
      t.references  :event_route,              null: true
      t.bigint      :route_owner_id,           null: true
      t.string      :action,                   null: false, limit: 50
      t.string      :group_key,                null: false, limit: 64
      t.text        :labels,                   null: false
      t.integer     :group_wait_seconds,       null: false
      t.integer     :group_interval_seconds,   null: false
      t.datetime    :next_flush_at,            null: true
      t.datetime    :last_sealed_at,           null: true
      t.timestamps                             null: false
    end

    add_index :event_delivery_groups, :group_key, unique: true
    add_index :event_delivery_groups, %i[action next_flush_at],
              name: 'idx_event_delivery_groups_on_action_due'

    create_table :event_delivery_attempts do |t|
      t.references  :event_delivery,           null: false
      t.string      :action,                   null: false, limit: 50
      t.integer     :state,                    null: false
      t.integer     :attempt_number,           null: false
      t.datetime    :started_at,               null: true
      t.datetime    :finished_at,              null: true
      t.string      :provider_message_id,      null: true, limit: 255
      t.integer     :response_status,          null: true
      t.text        :response_body,            null: true
      t.text        :response_headers,         null: true
      t.text        :error_summary,            null: true
      t.timestamps                             null: false
    end

    add_index :event_delivery_attempts, %i[event_delivery_id attempt_number],
              unique: true, name: 'idx_delivery_attempts_on_delivery_number'
    add_index :event_delivery_attempts, %i[action state],
              name: 'idx_delivery_attempts_on_action_state'
    add_index :event_delivery_attempts, :created_at

    backfill_default_routes
    backfill_advanced_mail_routes
  end

  def down
    drop_table :event_delivery_attempts
    drop_table :event_delivery_groups
    drop_table :event_deliveries
    drop_table :events
    drop_table :event_route_matchers
    drop_table :event_routes
    drop_table :notification_receiver_targets
    drop_table :notification_targets
    drop_table :notification_receivers
  end

  protected

  def backfill_default_routes
    return unless table_exists?(:users)

    say_with_time('Creating default event receivers and routes') do
      execute <<~SQL.squish
        INSERT INTO notification_receivers
          (user_id, label, description, enabled, mute, created_at, updated_at)
        SELECT
          id,
          CASE WHEN #{mailer_enabled_sql} = 1 THEN 'Default e-mail' ELSE 'Do not notify' END,
          CASE
            WHEN #{mailer_enabled_sql} = 1 THEN 'Created from the existing mailer setting'
            ELSE 'Created from the disabled mailer setting'
          END,
          1,
          CASE WHEN #{mailer_enabled_sql} = 1 THEN 0 ELSE 1 END,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM users
      SQL

      execute <<~SQL.squish
        INSERT INTO notification_targets
          (user_id, action, label, target_kind, target_value, identity_key,
           enabled, created_at, updated_at)
        SELECT
          notification_receivers.user_id,
          'email',
          'Default e-mail',
          0,
          NULL,
          'default',
          1,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
        INNER JOIN users ON users.id = notification_receivers.user_id
        WHERE #{mailer_enabled_sql} = 1
      SQL

      execute <<~SQL.squish
        INSERT INTO notification_receiver_targets
          (notification_receiver_id, notification_target_id, position, created_at, updated_at)
        SELECT
          notification_receivers.id,
          notification_targets.id,
          1,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
        INNER JOIN notification_targets
          ON notification_targets.user_id = notification_receivers.user_id
         AND notification_targets.action = 'email'
         AND notification_targets.identity_key = 'default'
        INNER JOIN users ON users.id = notification_receivers.user_id
        WHERE #{mailer_enabled_sql} = 1
      SQL

      execute <<~SQL.squish
        INSERT INTO event_routes
          (user_id, parent_id, notification_receiver_id, label, position,
           enabled, event_type, event_type_pattern, `continue`,
           single_use, spent_at, expires_at, hit_count,
           created_at, updated_at)
        SELECT
          user_id,
          NULL,
          id,
          'Default route',
          10000,
          1,
          NULL,
          NULL,
          0,
          0,
          NULL,
          NULL,
          0,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
      SQL

      execute <<~SQL.squish
        INSERT INTO event_routes
          (user_id, parent_id, notification_receiver_id, label, position,
           enabled, event_type, event_type_pattern, `continue`,
           single_use, spent_at, expires_at, hit_count,
           created_at, updated_at)
        SELECT
          user_id,
          NULL,
          id,
          'Default admin route',
          10001,
          1,
          NULL,
          NULL,
          0,
          0,
          NULL,
          NULL,
          0,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
      SQL

      execute <<~SQL.squish
        INSERT INTO event_route_matchers
          (event_route_id, field, operator, value, created_at, updated_at)
        SELECT
          event_routes.id,
          'default_routed',
          '==',
          'true',
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM event_routes
        WHERE event_routes.parent_id IS NULL
          AND event_routes.label IN ('Default route', 'Default admin route')
          AND event_routes.event_type IS NULL
          AND event_routes.event_type_pattern IS NULL
      SQL

      execute <<~SQL.squish
        INSERT INTO event_route_matchers
          (event_route_id, field, operator, value, created_at, updated_at)
        SELECT
          event_routes.id,
          'roles',
          'contains',
          CASE WHEN event_routes.label = 'Default admin route' THEN 'admin' ELSE 'account' END,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM event_routes
        WHERE event_routes.parent_id IS NULL
          AND event_routes.label IN ('Default route', 'Default admin route')
          AND event_routes.event_type IS NULL
          AND event_routes.event_type_pattern IS NULL
      SQL
    end
  end

  def backfill_advanced_mail_routes
    return unless table_exists?(:users)

    say_with_time('Creating event routes from advanced e-mail settings') do
      backfill_notification_template_recipient_routes
      backfill_email_role_recipient_routes
    end
  end

  def backfill_notification_template_recipient_routes
    return unless table_exists?(:user_notification_template_recipients)
    return unless table_exists?(:notification_templates)

    template_names = advanced_template_names
    positions = Hash.new(ADVANCED_NOTIFICATION_TEMPLATE_ROUTE_POSITION - 1)

    rows = select_all(<<~SQL.squish).to_a
      SELECT
        user_notification_template_recipients.*,
        notification_templates.name AS template_name,
        notification_templates.label AS template_label,
        #{mailer_enabled_sql} AS mailer_enabled
      FROM user_notification_template_recipients
      INNER JOIN notification_templates
        ON notification_templates.id = user_notification_template_recipients.notification_template_id
      INNER JOIN users ON users.id = user_notification_template_recipients.user_id
      WHERE notification_templates.name IN (#{quoted_list(template_names)})
      ORDER BY user_notification_template_recipients.user_id, notification_templates.name
    SQL

    rows.sort_by! { |row| advanced_mail_event_template_sort_key(row) }

    rows.each do |row|
      next unless truthy?(row.fetch('mailer_enabled'))

      cfg = advanced_mail_event_template_by_name.fetch(row.fetch('template_name'), nil)
      next unless cfg

      disabled = !truthy?(row.fetch('enabled'))
      target = row.fetch('to').to_s
      next if !disabled && target.strip.empty?

      user_id = row.fetch('user_id').to_i
      template_label = label_or_name(row.fetch('template_label'), row.fetch('template_name'))
      positions[user_id] += 1

      if disabled
        receiver_id = create_advanced_mail_receiver(
          user_id:,
          label: "#{template_label} disabled",
          description: 'Created from an advanced notification template setting',
          mute: true
        )
        route_label = "#{template_label} disabled"
      else
        receiver_id = create_advanced_mail_receiver(
          user_id:,
          label: "#{template_label} e-mail",
          description: 'Created from an advanced notification template recipient',
          mute: false
        )
        create_advanced_mail_target_link(
          receiver_id:,
          label: "#{template_label} e-mail",
          target_value: target
        )
        route_label = "#{template_label} e-mail"
      end

      create_advanced_mail_route(
        user_id:,
        receiver_id:,
        event_config: cfg,
        label: route_label,
        position: positions[user_id]
      )
    end
  end

  def backfill_email_role_recipient_routes
    return unless table_exists?(:user_email_role_recipients)

    positions = Hash.new(ADVANCED_EMAIL_ROLE_ROUTE_POSITION - 1)

    rows = select_all(<<~SQL.squish).to_a.select do |row|
      SELECT user_email_role_recipients.*, #{mailer_enabled_sql} AS mailer_enabled
      FROM user_email_role_recipients
      INNER JOIN users ON users.id = user_email_role_recipients.user_id
      WHERE user_email_role_recipients.role IN (#{quoted_list(advanced_email_roles)})
      ORDER BY user_email_role_recipients.user_id, user_email_role_recipients.role
    SQL
      truthy?(row.fetch('mailer_enabled')) && row.fetch('to').to_s.strip.present?
    end
    rows_by_user = rows.group_by { |row| row.fetch('user_id').to_i }

    rows.each do |row|
      role = row.fetch('role').to_s
      templates = advanced_mail_event_templates_for_role(role)
      next if templates.empty?

      user_id = row.fetch('user_id').to_i
      target = row.fetch('to').to_s
      role_label = ADVANCED_EMAIL_ROLE_LABELS.fetch(role, role)
      receiver_id = create_advanced_mail_receiver(
        user_id:,
        label: "#{role_label} e-mail",
        description: 'Created from an advanced e-email role recipient',
        mute: false
      )
      create_advanced_mail_target_link(
        receiver_id:,
        label: "#{role_label} e-mail",
        target_value: target
      )

      templates.each do |cfg|
        positions[user_id] += 1
        create_advanced_mail_route(
          user_id:,
          receiver_id:,
          event_config: cfg,
          label: "#{role_label} e-mail for #{cfg.fetch(:label)}",
          position: positions[user_id],
          role:,
          continue: continue_advanced_email_role_route?(
            rows_by_user.fetch(user_id),
            role,
            cfg
          )
        )
      end
    end
  end

  def create_advanced_mail_receiver(user_id:, label:, description:, mute:)
    insert_row(
      'notification_receivers',
      user_id:,
      label: limit_label(label),
      description:,
      enabled: true,
      mute:,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def create_advanced_mail_target_link(receiver_id:, label:, target_value:)
    receiver = select_one(<<~SQL.squish)
      SELECT user_id FROM notification_receivers WHERE id = #{quote(receiver_id)}
    SQL
    user_id = receiver.fetch('user_id').to_i
    identity_key = "custom:#{Digest::SHA256.hexdigest(target_value.to_s.gsub(/\s/, ''))}"
    target_id = select_value(<<~SQL.squish)
      SELECT id
      FROM notification_targets
      WHERE user_id = #{quote(user_id)}
        AND action = 'email'
        AND identity_key = #{quote(identity_key)}
      LIMIT 1
    SQL

    target_id ||= insert_row(
      'notification_targets',
      user_id:,
      action: 'email',
      label: limit_label(label),
      target_kind: 1,
      target_value:,
      identity_key:,
      enabled: true,
      verified_at: current_timestamp,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )

    insert_row(
      'notification_receiver_targets',
      notification_receiver_id: receiver_id,
      notification_target_id: target_id,
      position: next_receiver_target_position(receiver_id),
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def next_receiver_target_position(receiver_id)
    (select_value(<<~SQL.squish).to_i + 1)
      SELECT COALESCE(MAX(position), 0)
      FROM notification_receiver_targets
      WHERE notification_receiver_id = #{quote(receiver_id)}
    SQL
  end

  def create_advanced_mail_route(user_id:, receiver_id:, event_config:, label:, position:, role: nil, continue: false)
    route_id = insert_row(
      'event_routes',
      user_id:,
      parent_id: nil,
      notification_receiver_id: receiver_id,
      label: limit_label(label),
      position:,
      enabled: true,
      event_type: event_config.fetch(:event_type),
      event_type_pattern: nil,
      template_name: event_config.fetch(:template_name),
      continue:,
      hit_count: 0,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )

    if role
      create_event_route_matcher(
        route_id:,
        field: 'roles',
        operator: 'contains',
        value: role
      )
    end

    event_config.fetch(:matchers).each do |field, operator, value|
      create_event_route_matcher(route_id:, field:, operator:, value:)
    end

    route_id
  end

  def create_event_route_matcher(route_id:, field:, operator:, value:)
    insert_row(
      'event_route_matchers',
      event_route_id: route_id,
      field:,
      operator:,
      value:,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def advanced_mail_event_template_by_name
    @advanced_mail_event_template_by_name ||=
      ADVANCED_NOTIFICATION_EVENT_TEMPLATES.flat_map do |cfg|
        names = cfg.fetch(:legacy_template_names, [cfg.fetch(:template_name)])
        names.map { |name| [name, cfg] }
      end.to_h
  end

  def advanced_mail_event_templates_for_role(role)
    ADVANCED_NOTIFICATION_EVENT_TEMPLATES.select { |cfg| cfg.fetch(:roles).include?(role.to_s) }
  end

  def advanced_template_names
    ADVANCED_NOTIFICATION_EVENT_TEMPLATES.flat_map do |cfg|
      cfg.fetch(:legacy_template_names, [cfg.fetch(:template_name)])
    end
  end

  def advanced_mail_event_template_sort_key(row)
    cfg = advanced_mail_event_template_by_name.fetch(row.fetch('template_name'), nil)
    [
      row.fetch('user_id').to_i,
      cfg&.fetch(:priority, 0) || 0,
      row.fetch('template_name').to_s
    ]
  end

  def continue_advanced_email_role_route?(rows, role, cfg)
    roles = rows
            .map { |row| row.fetch('role').to_s }
            .select { |row_role| cfg.fetch(:roles).include?(row_role) }
    role_index = roles.index(role.to_s)

    !!(role_index && role_index < roles.length - 1)
  end

  def advanced_email_roles
    ADVANCED_NOTIFICATION_EVENT_TEMPLATES.flat_map { |cfg| cfg.fetch(:roles) }.uniq
  end

  def truthy?(value)
    value == true || value.to_s == '1'
  end

  def label_or_name(label, name)
    ret = label.to_s
    ret.empty? ? name.to_s : ret
  end

  def limit_label(value)
    value.to_s[0, 255]
  end

  def quoted_list(values)
    values.map { |v| quote(v) }.join(', ')
  end

  def insert_row(table, attrs)
    quoted_columns = attrs.keys.map { |name| quote_column_name(name) }.join(', ')
    quoted_values = attrs.values.map { |value| quote(value) }.join(', ')

    execute <<~SQL.squish
      INSERT INTO #{quote_table_name(table)} (#{quoted_columns})
      VALUES (#{quoted_values})
    SQL

    connection.select_value('SELECT LAST_INSERT_ID()').to_i
  end

  def select_all(sql)
    connection.select_all(sql)
  end

  def quote(value)
    connection.quote(value)
  end

  def quote_column_name(name)
    connection.quote_column_name(name)
  end

  def quote_table_name(name)
    connection.quote_table_name(name)
  end

  def current_timestamp
    @current_timestamp ||= Time.now.utc
  end

  def mailer_enabled_sql
    column_exists?(:users, :mailer_enabled) ? 'users.mailer_enabled' : '1'
  end
end
