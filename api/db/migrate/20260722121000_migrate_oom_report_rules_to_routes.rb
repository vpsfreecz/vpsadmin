class MigrateOomReportRulesToRoutes < ActiveRecord::Migration[8.1]
  DEFAULT_ROUTE_LABEL = 'Default route'.freeze
  IGNORED_RECEIVER_LABEL = 'Ignored OOM reports'.freeze

  def up
    validate_source_schema!

    say_with_time('Migrating OOM report rules to event routes') do
      source_count = select_value('SELECT COUNT(*) FROM oom_report_rules').to_i
      rules = legacy_rules

      if rules.length != source_count
        raise ActiveRecord::MigrationError,
              "expected #{source_count} OOM report rules with VPS owners, found #{rules.length}"
      end

      receiver_ids = default_receiver_ids
      default_positions = default_route_positions
      validate_route_prerequisites!(rules, receiver_ids, default_positions)
      ignored_receiver_ids = create_ignored_receivers(rules)
      route_ids = create_routes(
        rules,
        receiver_ids:,
        ignored_receiver_ids:,
        default_positions:
      )

      verify_conversion!(source_count, route_ids)
    end

    remove_column :oom_reports, :oom_report_rule_id
    remove_column :vpses, :implicit_oom_report_rule_hit_count
    drop_table :oom_report_rules
  end

  def down
    create_table :oom_report_rules do |t|
      t.references :vps, null: false
      t.integer :action, null: false
      t.string :cgroup_pattern, null: false
      t.bigint :hit_count, null: false, default: 0
      t.timestamps null: false
    end

    add_column :oom_reports, :oom_report_rule_id, :bigint, null: true
    add_column :vpses,
               :implicit_oom_report_rule_hit_count,
               :bigint,
               null: false,
               default: 0
  end

  protected

  def validate_source_schema!
    required_tables = %i[
      oom_report_rules
      oom_reports
      vpses
      notification_receivers
      event_routes
      event_route_matchers
    ]
    missing_tables = required_tables.reject { |table| table_exists?(table) }

    if missing_tables.any?
      raise ActiveRecord::MigrationError,
            "cannot migrate OOM report rules, missing tables: #{missing_tables.join(', ')}"
    end

    required_columns = {
      oom_reports: :oom_report_rule_id,
      vpses: :implicit_oom_report_rule_hit_count
    }
    missing_columns = required_columns.reject { |table, column| column_exists?(table, column) }

    return if missing_columns.empty?

    formatted = missing_columns.map { |table, column| "#{table}.#{column}" }
    raise ActiveRecord::MigrationError,
          "cannot migrate OOM report rules, missing columns: #{formatted.join(', ')}"
  end

  def legacy_rules
    select_all(<<~SQL.squish).to_a
      SELECT oom_report_rules.*, vpses.user_id
      FROM oom_report_rules
      INNER JOIN vpses ON vpses.id = oom_report_rules.vps_id
      ORDER BY vpses.user_id, oom_report_rules.id
    SQL
  end

  def default_receiver_ids
    select_all(<<~SQL.squish).to_h do |row|
      SELECT user_id, notification_receiver_id
      FROM event_routes
      WHERE parent_id IS NULL
        AND label = #{quote(DEFAULT_ROUTE_LABEL)}
        AND event_type IS NULL
        AND event_type_pattern IS NULL
      ORDER BY id
    SQL
      receiver_id = row.fetch('notification_receiver_id')
      [
        row.fetch('user_id').to_i,
        receiver_id.nil? ? nil : receiver_id.to_i
      ]
    end
  end

  def default_route_positions
    select_all(<<~SQL.squish).to_h do |row|
      SELECT user_id, MIN(position) AS position
      FROM event_routes
      WHERE parent_id IS NULL
        AND label IN (#{quote(DEFAULT_ROUTE_LABEL)}, 'Default admin route')
        AND event_type IS NULL
        AND event_type_pattern IS NULL
      GROUP BY user_id
    SQL
      [row.fetch('user_id').to_i, row.fetch('position').to_i]
    end
  end

  def validate_route_prerequisites!(rules, receiver_ids, default_positions)
    rules
      .map { |rule| rule.fetch('user_id').to_i }
      .uniq
      .each do |user_id|
        unless receiver_ids[user_id]
          raise ActiveRecord::MigrationError,
                "cannot migrate OOM report rules for user #{user_id}: default receiver not found"
        end

        next if default_positions[user_id]

        raise ActiveRecord::MigrationError,
              "cannot migrate OOM report rules for user #{user_id}: default route not found"
      end
  end

  def create_ignored_receivers(rules)
    rules
      .select { |rule| rule.fetch('action').to_i == 1 }
      .map { |rule| rule.fetch('user_id').to_i }
      .uniq
      .to_h do |user_id|
        [
          user_id,
          insert_row(
            :notification_receivers,
            user_id:,
            label: IGNORED_RECEIVER_LABEL,
            description: 'Created from OOM report ignore rules',
            enabled: true,
            mute: true,
            created_at: current_timestamp,
            updated_at: current_timestamp
          )
        ]
      end
  end

  def create_routes(rules, receiver_ids:, ignored_receiver_ids:, default_positions:)
    grouped_rules = rules.group_by { |rule| rule.fetch('user_id').to_i }

    grouped_rules.flat_map do |user_id, user_rules|
      first_position = make_room_before_default_routes(
        user_id,
        user_rules.length,
        default_positions.fetch(user_id)
      )

      user_rules.each_with_index.map do |rule, index|
        receiver_id =
          if rule.fetch('action').to_i == 1
            ignored_receiver_ids.fetch(user_id)
          else
            receiver_ids.fetch(user_id)
          end

        create_route(
          rule,
          user_id:,
          receiver_id:,
          position: first_position + index
        )
      end
    end
  end

  def make_room_before_default_routes(user_id, count, default_position)
    execute <<~SQL.squish
      UPDATE event_routes
      SET position = position + #{quote(count)}
      WHERE user_id = #{quote(user_id)}
        AND parent_id IS NULL
        AND position >= #{quote(default_position.to_i)}
    SQL

    default_position.to_i
  end

  def create_route(rule, user_id:, receiver_id:, position:)
    action = rule.fetch('action').to_i == 1 ? 'ignore' : 'notify'
    pattern = rule.fetch('cgroup_pattern').to_s
    route_id = insert_row(
      :event_routes,
      user_id:,
      parent_id: nil,
      notification_receiver_id: receiver_id,
      label: "OOM report #{action} #{pattern}"[0, 255],
      position:,
      enabled: true,
      event_type: 'vps.oom_report',
      event_type_pattern: nil,
      continue: false,
      hit_count: rule.fetch('hit_count').to_i,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )

    create_matcher(route_id, 'vps_id', '==', rule.fetch('vps_id').to_s)
    create_matcher(route_id, 'stage', '==', 'raw')
    create_matcher(route_id, 'cgroup', '=*', pattern)

    route_id
  end

  def create_matcher(route_id, field, operator, value)
    insert_row(
      :event_route_matchers,
      event_route_id: route_id,
      field:,
      operator:,
      value:,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def verify_conversion!(source_count, route_ids)
    if route_ids.length != source_count
      raise ActiveRecord::MigrationError,
            "expected #{source_count} migrated OOM report routes, created #{route_ids.length}"
    end

    matcher_count =
      if route_ids.empty?
        0
      else
        select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM event_route_matchers
          WHERE event_route_id IN (#{route_ids.map { |id| quote(id) }.join(', ')})
        SQL
      end

    return if matcher_count == source_count * 3

    raise ActiveRecord::MigrationError,
          "expected #{source_count * 3} migrated OOM report matchers, created #{matcher_count}"
  end

  def insert_row(table, attrs)
    columns = attrs.keys.map { |name| quote_column_name(name) }.join(', ')
    values = attrs.values.map { |value| quote(value) }.join(', ')

    execute <<~SQL.squish
      INSERT INTO #{quote_table_name(table)} (#{columns})
      VALUES (#{values})
    SQL

    select_value('SELECT LAST_INSERT_ID()').to_i
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
    connection.select_value('SELECT CURRENT_TIMESTAMP')
  end
end
