class AddEvents < ActiveRecord::Migration[8.1]
  ADVANCED_MAIL_TEMPLATE_ROUTE_POSITION = 10
  ADVANCED_MAIL_ROLE_ROUTE_POSITION = 1_000
  ADVANCED_MAIL_EVENT_TEMPLATES = [
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
      matchers: [
        ['parameters.stage', '==', 'notification']
      ]
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
    }
  ].freeze
  ADVANCED_MAIL_ROLE_LABELS = {
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

    create_table :notification_receiver_actions do |t|
      t.references  :notification_receiver,    null: false,
                                               index: { name: 'idx_receiver_actions_on_receiver' }
      t.integer     :action,                   null: false
      t.string      :label,                    null: true, limit: 255
      t.integer     :target_kind,              null: false, default: 0
      t.text        :target_value,             null: true
      t.string      :template_name,            null: true, limit: 100
      t.text        :config,                   null: true
      t.text        :secret,                   null: true
      t.string      :verification_token,       null: true, limit: 255
      t.datetime    :verified_at,              null: true
      t.boolean     :enabled,                  null: false, default: true
      t.text        :last_error,               null: true
      t.timestamps                             null: false
    end

    add_index :notification_receiver_actions, %i[notification_receiver_id action enabled],
              name: 'idx_receiver_actions_on_receiver_action_enabled'
    add_index :notification_receiver_actions, :verification_token, unique: true

    create_table :event_routes do |t|
      t.references  :user,                     null: false
      t.bigint      :parent_id,                null: true
      t.bigint      :notification_receiver_id, null: true
      t.string      :label,                    null: true, limit: 255
      t.integer     :position,                 null: false, default: 0
      t.boolean     :enabled,                  null: false, default: true
      t.string      :event_type,               null: true, limit: 100
      t.string      :event_type_pattern,       null: true, limit: 100
      t.boolean     :continue,                 null: false, default: false
      t.bigint      :hit_count,                null: false, default: 0
      t.timestamps                             null: false
    end

    add_index :event_routes, %i[user_id parent_id position id],
              name: 'index_event_routes_on_user_parent_position'
    add_index :event_routes, :enabled
    add_index :event_routes, :event_type
    add_index :event_routes, :parent_id
    add_index :event_routes, :notification_receiver_id

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
      t.references  :notification_receiver_action, null: true,
                                                   index: { name: 'idx_event_deliveries_on_receiver_action' }
      t.integer     :action,                   null: false
      t.integer     :target_kind,              null: false
      t.text        :target_value,             null: true
      t.string      :target_label,             null: true, limit: 255
      t.string      :template_name,            null: true, limit: 100
      t.integer     :state,                    null: false
      t.integer     :mail_log_id,              null: true
      t.integer     :transaction_id,           null: true
      t.integer     :attempt_count,            null: false, default: 0
      t.datetime    :next_attempt_at,          null: true
      t.datetime    :last_attempt_at,          null: true
      t.string      :provider_message_id,      null: true, limit: 255
      t.integer     :response_status,          null: true
      t.text        :response_body,            null: true
      t.text        :error_summary,            null: true
      t.timestamps                             null: false
    end

    add_index :event_deliveries, %i[event_id action state]
    add_index :event_deliveries, :state
    add_index :event_deliveries, :next_attempt_at
    add_index :event_deliveries, :mail_log_id
    add_index :event_deliveries, :transaction_id

    backfill_default_routes
    backfill_advanced_mail_routes
    backfill_oom_report_routes
  end

  def down
    drop_table :event_deliveries
    drop_table :events
    drop_table :event_route_matchers
    drop_table :event_routes
    drop_table :notification_receiver_actions
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
          CASE WHEN mailer_enabled = 1 THEN 'Default e-mail' ELSE 'Do not notify' END,
          CASE
            WHEN mailer_enabled = 1 THEN 'Created from the existing mailer setting'
            ELSE 'Created from the disabled mailer setting'
          END,
          1,
          CASE WHEN mailer_enabled = 1 THEN 0 ELSE 1 END,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM users
      SQL

      execute <<~SQL.squish
        INSERT INTO notification_receiver_actions
          (notification_receiver_id, action, label, target_kind, target_value,
           template_name, enabled, created_at, updated_at)
        SELECT
          notification_receivers.id,
          0,
          'Default e-mail',
          0,
          NULL,
          NULL,
          1,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
        INNER JOIN users ON users.id = notification_receivers.user_id
        WHERE users.mailer_enabled = 1
      SQL

      execute <<~SQL.squish
        INSERT INTO event_routes
          (user_id, parent_id, notification_receiver_id, label, position,
           enabled, event_type, event_type_pattern, `continue`, hit_count,
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
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
      SQL
    end
  end

  def backfill_oom_report_routes
    return unless table_exists?(:oom_report_rules)
    return unless table_exists?(:vpses)

    say_with_time('Creating event routes from OOM report rules') do
      ignored_receivers = backfill_oom_ignored_receivers
      default_receivers = default_receiver_ids
      positions = Hash.new(100)

      select_all(<<~SQL.squish).each do |rule|
        SELECT oom_report_rules.*, vpses.user_id
        FROM oom_report_rules
        INNER JOIN vpses ON vpses.id = oom_report_rules.vps_id
        ORDER BY vpses.user_id, oom_report_rules.id
      SQL
        user_id = rule.fetch('user_id').to_i
        receiver_id =
          if rule.fetch('action').to_i == 1
            ignored_receivers.fetch(user_id)
          else
            default_receivers[user_id]
          end
        next unless receiver_id

        positions[user_id] += 1
        route_id = create_oom_report_route(
          user_id:,
          receiver_id:,
          rule:,
          position: positions[user_id]
        )

        create_event_route_matcher(
          route_id:,
          field: 'vps_id',
          operator: '==',
          value: rule.fetch('vps_id').to_s
        )
        create_event_route_matcher(
          route_id:,
          field: 'parameters.stage',
          operator: '==',
          value: 'raw'
        )
        create_event_route_matcher(
          route_id:,
          field: 'parameters.cgroup',
          operator: '=*',
          value: rule.fetch('cgroup_pattern')
        )
      end
    end
  end

  def backfill_advanced_mail_routes
    return unless table_exists?(:users)

    say_with_time('Creating event routes from advanced e-mail settings') do
      backfill_mail_template_recipient_routes
      backfill_mail_role_recipient_routes
    end
  end

  def backfill_mail_template_recipient_routes
    return unless table_exists?(:user_mail_template_recipients)
    return unless table_exists?(:mail_templates)

    template_names = ADVANCED_MAIL_EVENT_TEMPLATES.map { |cfg| cfg.fetch(:template_name) }
    positions = Hash.new(ADVANCED_MAIL_TEMPLATE_ROUTE_POSITION - 1)

    select_all(<<~SQL.squish).each do |row|
      SELECT
        user_mail_template_recipients.*,
        mail_templates.name AS template_name,
        mail_templates.label AS template_label,
        users.mailer_enabled
      FROM user_mail_template_recipients
      INNER JOIN mail_templates
        ON mail_templates.id = user_mail_template_recipients.mail_template_id
      INNER JOIN users ON users.id = user_mail_template_recipients.user_id
      WHERE mail_templates.name IN (#{quoted_list(template_names)})
      ORDER BY user_mail_template_recipients.user_id, mail_templates.name
    SQL
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
          description: 'Created from an advanced e-mail template setting',
          mute: true
        )
        route_label = "#{template_label} disabled"
      else
        receiver_id = create_advanced_mail_receiver(
          user_id:,
          label: "#{template_label} e-mail",
          description: 'Created from an advanced e-mail template recipient',
          mute: false
        )
        create_advanced_mail_action(
          receiver_id:,
          label: "#{template_label} e-mail",
          target_value: target,
          template_name: cfg.fetch(:template_name)
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

  def backfill_mail_role_recipient_routes
    return unless table_exists?(:user_mail_role_recipients)

    positions = Hash.new(ADVANCED_MAIL_ROLE_ROUTE_POSITION - 1)

    rows = select_all(<<~SQL.squish).to_a.select do |row|
      SELECT user_mail_role_recipients.*, users.mailer_enabled
      FROM user_mail_role_recipients
      INNER JOIN users ON users.id = user_mail_role_recipients.user_id
      WHERE user_mail_role_recipients.role IN (#{quoted_list(advanced_mail_roles)})
      ORDER BY user_mail_role_recipients.user_id, user_mail_role_recipients.role
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
      role_label = ADVANCED_MAIL_ROLE_LABELS.fetch(role, role)
      receiver_id = create_advanced_mail_receiver(
        user_id:,
        label: "#{role_label} e-mail",
        description: 'Created from an advanced e-mail role recipient',
        mute: false
      )
      create_advanced_mail_action(
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
          continue: continue_advanced_mail_role_route?(
            rows_by_user.fetch(user_id),
            role,
            cfg
          )
        )
      end
    end
  end

  def backfill_oom_ignored_receivers
    ret = {}

    select_all(<<~SQL.squish).each do |row|
      SELECT DISTINCT vpses.user_id
      FROM oom_report_rules
      INNER JOIN vpses ON vpses.id = oom_report_rules.vps_id
      WHERE oom_report_rules.action = 1
    SQL
      user_id = row.fetch('user_id').to_i
      ret[user_id] = insert_row(
        'notification_receivers',
        user_id:,
        label: 'Ignored OOM reports',
        description: 'Created from OOM report ignore rules',
        enabled: true,
        mute: true,
        created_at: current_timestamp,
        updated_at: current_timestamp
      )
    end

    ret
  end

  def default_receiver_ids
    ret = {}

    select_all(<<~SQL.squish).each do |row|
      SELECT user_id, notification_receiver_id
      FROM event_routes
      WHERE parent_id IS NULL
        AND label = 'Default route'
        AND event_type IS NULL
        AND event_type_pattern IS NULL
    SQL
      ret[row.fetch('user_id').to_i] = row.fetch('notification_receiver_id').to_i
    end

    ret
  end

  def create_oom_report_route(user_id:, receiver_id:, rule:, position:)
    action = rule.fetch('action').to_i == 1 ? 'ignore' : 'notify'
    pattern = rule.fetch('cgroup_pattern').to_s

    insert_row(
      'event_routes',
      user_id:,
      parent_id: nil,
      notification_receiver_id: receiver_id,
      label: "OOM report #{action} #{pattern}"[0, 255],
      position:,
      enabled: true,
      event_type: 'vps.oom_report',
      event_type_pattern: nil,
      continue: false,
      hit_count: 0,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
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

  def create_advanced_mail_action(receiver_id:, label:, target_value:, template_name: nil)
    insert_row(
      'notification_receiver_actions',
      notification_receiver_id: receiver_id,
      action: 0,
      label: limit_label(label),
      target_kind: 1,
      target_value:,
      template_name:,
      enabled: true,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def create_advanced_mail_route(user_id:, receiver_id:, event_config:, label:, position:, continue: false)
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
      continue:,
      hit_count: 0,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )

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
      ADVANCED_MAIL_EVENT_TEMPLATES.to_h { |cfg| [cfg.fetch(:template_name), cfg] }
  end

  def advanced_mail_event_templates_for_role(role)
    ADVANCED_MAIL_EVENT_TEMPLATES.select { |cfg| cfg.fetch(:roles).include?(role.to_s) }
  end

  def continue_advanced_mail_role_route?(rows, role, cfg)
    roles = rows
            .map { |row| row.fetch('role').to_s }
            .select { |row_role| cfg.fetch(:roles).include?(row_role) }
    role_index = roles.index(role.to_s)

    !!(role_index && role_index < roles.length - 1)
  end

  def advanced_mail_roles
    ADVANCED_MAIL_EVENT_TEMPLATES.flat_map { |cfg| cfg.fetch(:roles) }.uniq
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
end
