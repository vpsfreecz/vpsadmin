require 'digest'

class MigrateLegacyEmailRecipientsToRoutes < ActiveRecord::Migration[8.1]
  USER_LEVEL_ADMIN = 90
  DEFAULT_TARGET_KIND = 0
  CUSTOM_TARGET_KIND = 1
  SUBJECT_SCOPE_VISIBLE = 1
  REQUEST_TEMPLATE_TYPES = %w[registration change].freeze
  REQUEST_TEMPLATE_ROLES = %w[user admin].freeze
  REQUEST_TEMPLATE_RESOLVE_STATES = %w[approved denied ignored pending_correction awaiting].freeze

  def self.monitoring_matchers(role, monitor, state)
    [
      ['parameters.role', '==', role],
      ['parameters.monitor_name', '==', monitor],
      ['parameters.state', '==', state]
    ]
  end

  def self.request_route_entries
    ret = []

    %w[create update].each do |action|
      event_type = action == 'create' ? 'request.created' : 'request.updated'

      REQUEST_TEMPLATE_ROLES.each do |role|
        REQUEST_TEMPLATE_TYPES.each do |type|
          ret << [
            "request_#{action}_#{role}_#{type}",
            {
              event_type:,
              template_name: 'request_action_role_type',
              relation: 'other_user',
              matchers: [
                ['parameters.role', '==', role],
                ['parameters.request_type', '==', type]
              ]
            }
          ]
        end

        ret << [
          "request_#{action}_#{role}",
          {
            event_type:,
            template_name: 'request_action_role',
            relation: 'other_user',
            matchers: [
              ['parameters.role', '==', role]
            ]
          }
        ]
      end
    end

    REQUEST_TEMPLATE_ROLES.each do |role|
      REQUEST_TEMPLATE_TYPES.each do |type|
        REQUEST_TEMPLATE_RESOLVE_STATES.each do |state|
          ret << [
            "request_resolve_#{role}_#{type}_#{state}",
            {
              event_type: 'request.resolved',
              template_name: 'request_resolve_role_type_state',
              relation: 'other_user',
              matchers: [
                ['parameters.role', '==', role],
                ['parameters.request_type', '==', type],
                ['parameters.request_state', '==', state]
              ]
            }
          ]
        end

        ret << [
          "request_resolve_#{role}_#{type}",
          {
            event_type: 'request.resolved',
            template_name: 'request_action_role_type',
            relation: 'other_user',
            matchers: [
              ['parameters.role', '==', role],
              ['parameters.request_type', '==', type]
            ]
          }
        ]
      end

      REQUEST_TEMPLATE_RESOLVE_STATES.each do |state|
        ret << [
          "request_resolve_#{role}_#{state}",
          {
            event_type: 'request.resolved',
            template_name: 'request_resolve_role_state',
            relation: 'other_user',
            matchers: [
              ['parameters.role', '==', role],
              ['parameters.request_state', '==', state]
            ]
          }
        ]
      end

      ret << [
        "request_resolve_#{role}",
        {
          event_type: 'request.resolved',
          template_name: 'request_action_role',
          relation: 'other_user',
          matchers: [
            ['parameters.role', '==', role]
          ]
        }
      ]
    end

    ret
  end

  EVENT_TEMPLATE_ROUTE_MAP = {
    'user_new_login' => {
      event_type: 'user.new_login',
      template_name: 'user_new_login',
      relation: 'other_user',
      matchers: []
    },
    'user_new_token' => {
      event_type: 'user.new_token',
      template_name: 'user_new_token',
      relation: 'other_user',
      matchers: []
    },
    'user_totp_recovery_code_used' => {
      event_type: 'user.totp_recovery_code_used',
      template_name: 'user_totp_recovery_code_used',
      relation: 'other_user',
      matchers: []
    },
    'user_failed_logins' => {
      event_type: 'user.failed_logins',
      template_name: 'user_failed_logins',
      relation: 'other_user',
      matchers: []
    },
    'expiration_vps_active' => {
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning',
      relation: 'other_user',
      matchers: [
        ['parameters.object', '==', 'vps'],
        ['parameters.state', '==', 'active']
      ]
    },
    'payment_accepted' => {
      event_type: 'payment.accepted',
      template_name: 'payment_accepted',
      relation: 'other_user',
      matchers: []
    },
    'outage_report_user_announce' => {
      event_type: 'outage.announced',
      template_name: 'outage_report_role_event',
      relation: 'other_user',
      matchers: [
        ['parameters.role', '==', 'user']
      ]
    },
    'outage_report_user_update' => {
      event_type: 'outage.updated',
      template_name: 'outage_report_role_event',
      relation: 'other_user',
      matchers: [
        ['parameters.role', '==', 'user']
      ]
    },
    'security_advisory_user_announce' => {
      event_type: 'security_advisory.announced',
      template_name: 'security_advisory_user_announce',
      relation: 'other_user',
      matchers: []
    },
    'security_advisory_user_update' => {
      event_type: 'security_advisory.updated',
      template_name: 'security_advisory_user_update',
      relation: 'other_user',
      matchers: []
    },
    'vps_incident_report' => {
      event_type: 'vps.incident_report',
      template_name: 'vps_incident_report',
      relation: 'other_user',
      matchers: []
    },
    'vps_oom_report' => {
      event_type: 'vps.oom_report',
      template_name: 'vps_oom_report',
      relation: 'other_user',
      matchers: [
        ['parameters.stage', '==', 'notification']
      ]
    },
    'vps_oom_prevention' => {
      event_type: 'vps.oom_prevention',
      template_name: 'vps_oom_prevention',
      relation: 'other_user',
      matchers: []
    },
    'vps_suspend' => {
      event_type: 'vps.suspended',
      template_name: 'vps_suspend',
      relation: 'other_user',
      matchers: []
    },
    'vps_resume' => {
      event_type: 'vps.resumed',
      template_name: 'vps_resume',
      relation: 'other_user',
      matchers: []
    },
    'vps_resources_change' => {
      event_type: 'vps.resources_changed',
      template_name: 'vps_resources_change',
      relation: 'other_user',
      matchers: []
    },
    'vps_dns_resolver_change' => {
      event_type: 'vps.dns_resolver_changed',
      template_name: 'vps_dns_resolver_change',
      relation: 'other_user',
      matchers: []
    },
    'vps_network_disabled' => {
      event_type: 'vps.network_disabled',
      template_name: 'vps_network_disabled',
      relation: 'other_user',
      matchers: []
    },
    'vps_network_enabled' => {
      event_type: 'vps.network_enabled',
      template_name: 'vps_network_enabled',
      relation: 'other_user',
      matchers: []
    },
    'vps_stopped_over_quota' => {
      event_type: 'vps.stopped_over_quota',
      template_name: 'vps_stopped_over_quota',
      relation: 'other_user',
      matchers: []
    },
    'vps_dataset_expanded' => {
      event_type: 'vps.dataset_expanded',
      template_name: 'vps_dataset_expanded',
      relation: 'other_user',
      matchers: []
    },
    'vps_dataset_shrunk' => {
      event_type: 'vps.dataset_shrunk',
      template_name: 'vps_dataset_shrunk',
      relation: 'other_user',
      matchers: []
    },
    'snapshot_download_ready' => {
      event_type: 'snapshot.download_ready',
      template_name: 'snapshot_download_ready',
      relation: 'other_user',
      matchers: []
    },
    'dataset_migration_begun' => {
      event_type: 'dataset.migration_begun',
      template_name: 'dataset_migration_begun',
      relation: 'other_user',
      matchers: []
    },
    'dataset_migration_finished' => {
      event_type: 'dataset.migration_finished',
      template_name: 'dataset_migration_finished',
      relation: 'other_user',
      matchers: []
    },
    'vps_migration_planned' => {
      event_type: 'vps.migration_planned',
      template_name: 'vps_migration_planned',
      relation: 'other_user',
      matchers: []
    },
    'vps_migration_begun' => {
      event_type: 'vps.migration_begun',
      template_name: 'vps_migration_begun',
      relation: 'other_user',
      matchers: []
    },
    'vps_migration_finished' => {
      event_type: 'vps.migration_finished',
      template_name: 'vps_migration_finished',
      relation: 'other_user',
      matchers: []
    },
    'vps_replaced' => {
      event_type: 'vps.replaced',
      template_name: 'vps_replaced',
      relation: 'other_user',
      matchers: []
    }
  }.merge(request_route_entries.to_h).freeze

  TEMPLATE_ROUTE_MAP = {
    'daily_report' => {
      event_type: 'system.daily_report',
      template_name: 'daily_report',
      matchers: []
    },
    'payments_overview' => {
      event_type: 'payments.overview',
      template_name: 'payments_overview',
      matchers: []
    },
    'user_create' => {
      event_type: 'user.created',
      template_name: 'user_create',
      relation: 'other_user',
      matchers: []
    },
    'user_suspend' => {
      event_type: 'user.suspended',
      template_name: 'user_suspend',
      relation: 'other_user',
      matchers: []
    },
    'user_soft_delete' => {
      event_type: 'user.soft_deleted',
      template_name: 'user_soft_delete',
      relation: 'other_user',
      matchers: []
    },
    'user_resume' => {
      event_type: 'user.resumed',
      template_name: 'user_resume',
      relation: 'other_user',
      matchers: []
    },
    'user_revive' => {
      event_type: 'user.revived',
      template_name: 'user_revive',
      relation: 'other_user',
      matchers: []
    },
    'expiration_user_active' => {
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning',
      relation: 'other_user',
      matchers: [
        ['parameters.object', '==', 'user'],
        ['parameters.state', '==', 'active']
      ]
    },
    'alert_admin_monthly_traffic_closed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('admin', 'monthly_traffic', 'closed')
    },
    'alert_admin_monthly_traffic_confirmed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('admin', 'monthly_traffic', 'acknowledged')
    },
    'alert_admin_unpaid_cpu_closed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('admin', 'unpaid_cpu', 'closed')
    },
    'alert_admin_unpaid_cpu_confirmed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('admin', 'unpaid_cpu', 'acknowledged')
    },
    'alert_admin_unpaid_data_flow_closed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('admin', 'unpaid_data_flow', 'closed')
    },
    'alert_admin_unpaid_data_flow_confirmed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('admin', 'unpaid_data_flow', 'acknowledged')
    },
    'alert_user_paid_cpu_closed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('user', 'paid_cpu', 'closed')
    },
    'alert_user_paid_cpu_confirmed' => {
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state',
      relation: 'other_user',
      matchers: monitoring_matchers('user', 'paid_cpu', 'acknowledged')
    }
  }.merge(EVENT_TEMPLATE_ROUTE_MAP).freeze

  def up
    migrate_template_recipients if table_exists?(:notification_template_email_recipients)

    drop_table :notification_template_email_recipients, if_exists: true
    drop_table :email_recipients, if_exists: true
    drop_table :user_notification_template_recipients, if_exists: true
    drop_table :user_email_role_recipients, if_exists: true
  end

  def down
    create_table :email_recipients, id: { type: :integer, unsigned: true }, if_not_exists: true do |t|
      t.string :label, limit: 100, null: false
      t.string :to, limit: 500
      t.string :cc, limit: 500
      t.string :bcc, limit: 500
    end

    create_table :notification_template_email_recipients,
                 id: { type: :integer, unsigned: true },
                 if_not_exists: true do |t|
      t.integer :notification_template_id, null: false
      t.integer :email_recipient_id, null: false
    end
    add_index :notification_template_email_recipients,
              %i[notification_template_id email_recipient_id],
              unique: true,
              name: :notification_template_email_recipients_unique,
              if_not_exists: true

    create_table :user_email_role_recipients,
                 id: { type: :integer, unsigned: true },
                 if_not_exists: true do |t|
      t.integer :user_id, null: false
      t.string :role, limit: 100, null: false
      t.string :to, limit: 500
    end
    add_index :user_email_role_recipients, %i[user_id role],
              unique: true,
              name: :index_user_email_role_recipients_on_user_id_and_role,
              if_not_exists: true
    add_index :user_email_role_recipients, :user_id, if_not_exists: true

    create_table :user_notification_template_recipients,
                 id: { type: :integer, unsigned: true },
                 if_not_exists: true do |t|
      t.integer :user_id, null: false
      t.integer :notification_template_id, null: false
      t.string :to, limit: 500
      t.boolean :enabled, null: false, default: true
    end
    add_index :user_notification_template_recipients, %i[user_id notification_template_id],
              unique: true,
              name: :user_id_notification_template_id,
              if_not_exists: true
  end

  protected

  def migrate_template_recipients
    rows = select_all(<<~SQL.squish).to_a
      SELECT
        notification_templates.name AS template_name,
        notification_templates.label AS template_label,
        email_recipients.label AS recipient_label,
        email_recipients.to,
        email_recipients.cc,
        email_recipients.bcc
      FROM notification_template_email_recipients
      INNER JOIN notification_templates
        ON notification_templates.id = notification_template_email_recipients.notification_template_id
      INNER JOIN email_recipients
        ON email_recipients.id = notification_template_email_recipients.email_recipient_id
      ORDER BY notification_templates.name, email_recipients.id
    SQL

    unknown_templates = rows.map { |row| row.fetch('template_name') }.uniq - TEMPLATE_ROUTE_MAP.keys
    if unknown_templates.any?
      raise "cannot migrate legacy notification template recipients for unknown templates: #{unknown_templates.join(', ')}"
    end

    say_with_time('Creating event routes from legacy notification template recipients') do
      rows.each do |row|
        config = TEMPLATE_ROUTE_MAP.fetch(row.fetch('template_name'))

        email_addresses(row).each do |address|
          user = resolve_recipient_user!(address, row.fetch('recipient_label'))
          ensure_admin_visibility!(user, row, address)
          receiver_id = ensure_receiver(user, address)
          route_id = ensure_route(user, receiver_id, row, config)
          ensure_route_matchers(route_id, config)
        end
      end
    end
  end

  def email_addresses(row)
    %w[to cc bcc].flat_map do |attr|
      row[attr].to_s.split(',').map(&:strip)
    end.reject(&:blank?).uniq
  end

  def resolve_recipient_user!(address, label)
    users = select_all(<<~SQL.squish).to_a
      SELECT id, login, email, level
      FROM users
      WHERE LOWER(email) = LOWER(#{quote(address)})
    SQL
    return users.sole if users.length == 1

    if users.empty? && label.to_s.present?
      by_label = select_all(<<~SQL.squish).to_a
        SELECT id, login, email, level
        FROM users
        WHERE login = #{quote(label.to_s)}
      SQL
      return by_label.sole if by_label.length == 1
    end

    raise "cannot resolve legacy notification recipient #{address.inspect} (label #{label.inspect}) to exactly one user"
  end

  def ensure_admin_visibility!(user, row, address)
    return if user.fetch('level').to_i >= USER_LEVEL_ADMIN

    raise "legacy recipient #{address.inspect} for #{row.fetch('template_name')} resolves to non-admin user #{user.fetch('login')}"
  end

  def ensure_receiver(user, address)
    user_id = user.fetch('id').to_i
    label = limit_label("Legacy operational e-mail #{address}")
    existing = select_value(<<~SQL.squish)
      SELECT id
      FROM notification_receivers
      WHERE user_id = #{quote(user_id)}
        AND label = #{quote(label)}
      LIMIT 1
    SQL
    return existing.to_i if existing

    receiver_id = insert_row(
      'notification_receivers',
      user_id:,
      label:,
      description: 'Created from legacy notification template e-mail recipients',
      enabled: true,
      mute: false,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )

    target_id = ensure_target(user, address)
    insert_row(
      'notification_receiver_targets',
      notification_receiver_id: receiver_id,
      notification_target_id: target_id,
      position: 1,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
    receiver_id
  end

  def ensure_target(user, address)
    user_id = user.fetch('id').to_i
    target_value = same_email?(user.fetch('email'), address) ? nil : address
    identity_key =
      if target_value
        "custom:#{Digest::SHA256.hexdigest(target_value.gsub(/\s/, ''))}"
      else
        'default'
      end
    existing = select_value(<<~SQL.squish)
      SELECT id
      FROM notification_targets
      WHERE user_id = #{quote(user_id)}
        AND action = 'email'
        AND identity_key = #{quote(identity_key)}
      LIMIT 1
    SQL
    return existing.to_i if existing

    insert_row(
      'notification_targets',
      user_id:,
      action: 'email',
      label: target_value ? limit_label("Legacy #{address}") : 'Default e-mail',
      target_kind: target_value ? CUSTOM_TARGET_KIND : DEFAULT_TARGET_KIND,
      target_value:,
      identity_key:,
      enabled: true,
      verified_at: current_timestamp,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def ensure_route(user, receiver_id, row, config)
    user_id = user.fetch('id').to_i
    label = limit_label("Legacy #{row.fetch('template_label').presence || row.fetch('template_name')}")
    existing = select_value(<<~SQL.squish)
      SELECT id
      FROM event_routes
      WHERE user_id = #{quote(user_id)}
        AND notification_receiver_id = #{quote(receiver_id)}
        AND label = #{quote(label)}
        AND event_type = #{quote(config.fetch(:event_type))}
        AND template_name = #{quote(config.fetch(:template_name))}
        AND subject_scope = #{quote(SUBJECT_SCOPE_VISIBLE)}
      LIMIT 1
    SQL
    return existing.to_i if existing

    insert_row(
      'event_routes',
      user_id:,
      parent_id: nil,
      notification_receiver_id: receiver_id,
      label:,
      position: next_route_position(user_id),
      enabled: true,
      event_type: config.fetch(:event_type),
      event_type_pattern: nil,
      template_name: config.fetch(:template_name),
      subject_scope: SUBJECT_SCOPE_VISIBLE,
      continue: false,
      single_use: false,
      spent_at: nil,
      expires_at: nil,
      hit_count: 0,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def ensure_route_matchers(route_id, config)
    matchers = []
    matchers << ['context.subject_relation', '==', config.fetch(:relation)] if config[:relation]
    matchers.concat(config.fetch(:matchers))

    matchers.each do |field, operator, value|
      next if select_value(<<~SQL.squish)
        SELECT id
        FROM event_route_matchers
        WHERE event_route_id = #{quote(route_id)}
          AND field = #{quote(field)}
          AND operator = #{quote(operator)}
          AND value = #{quote(value)}
        LIMIT 1
      SQL

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
  end

  def next_route_position(user_id)
    select_value(<<~SQL.squish).to_i + 1
      SELECT COALESCE(MAX(position), 0)
      FROM event_routes
      WHERE user_id = #{quote(user_id)}
        AND parent_id IS NULL
        AND position < 10000
    SQL
  end

  def same_email?(a, b)
    a.to_s.casecmp(b.to_s) == 0
  end

  def limit_label(value)
    value.to_s[0, 255]
  end

  def insert_row(table, attrs)
    execute <<~SQL.squish
      INSERT INTO #{quote_table_name(table)}
        (#{attrs.keys.map { |name| quote_column_name(name) }.join(', ')})
      VALUES
        (#{attrs.values.map { |value| quote(value) }.join(', ')})
    SQL

    connection.select_value('SELECT LAST_INSERT_ID()').to_i
  end

  def select_all(sql)
    connection.select_all(sql)
  end

  def select_value(sql)
    connection.select_value(sql)
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
end
