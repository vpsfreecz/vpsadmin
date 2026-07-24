require 'json'

class MigrateOomReportRulesToRoutes < ActiveRecord::Migration[8.1]
  DEFAULT_ADMIN_ROUTE_LABEL = 'Default admin route'.freeze
  IGNORED_RECEIVER_LABEL = 'Ignored OOM reports'.freeze
  OOM_EVENT_TYPE = 'vps.oom_report'.freeze
  GROUP_WAIT_SECONDS = 60
  GROUP_INTERVAL_SECONDS = 3 * 60 * 60

  def up
    validate_source_schema!

    say_with_time('Migrating OOM report rules to grouped event routes') do
      source_count = select_value('SELECT COUNT(*) FROM oom_report_rules').to_i
      rules = legacy_rules
      if rules.length != source_count
        raise ActiveRecord::MigrationError,
              "expected #{source_count} OOM report rules with VPS owners, found #{rules.length}"
      end

      defaults = default_admin_routes
      validate_default_routes!(rules, defaults)
      recipients = effective_oom_receiver_ids(defaults)
      implicit_hits = implicit_hit_counts
      ignored_receivers = create_ignored_receivers(rules)

      remove_legacy_oom_recipient_routes!

      route_ids = []
      catch_all_ids = []
      rules.group_by { |rule| rule.fetch('user_id').to_i }.each do |user_id, user_rules|
        make_room_at_route_start(user_id, user_rules.length + 1)

        user_rules.each_with_index do |rule, index|
          receiver_id =
            if ignore_rule?(rule)
              ignored_receivers.fetch(user_id)
            else
              recipients.fetch(user_id)
            end
          route_ids << create_rule_route(
            rule,
            user_id:,
            receiver_id:,
            position: index
          )
        end

        catch_all_ids << create_catch_all_route(
          user_id:,
          receiver_id: recipients.fetch(user_id),
          position: user_rules.length,
          hit_count: implicit_hits.fetch(user_id, 0)
        )
      end

      users_without_rules = defaults.keys - rules.map { |rule| rule.fetch('user_id').to_i }.uniq
      users_without_rules.each do |user_id|
        make_room_at_route_start(user_id, 1)
        catch_all_ids << create_catch_all_route(
          user_id:,
          receiver_id: recipients.fetch(user_id),
          position: 0,
          hit_count: implicit_hits.fetch(user_id, 0)
        )
      end

      verify_conversion!(
        source_count:,
        route_ids:,
        catch_all_ids:,
        expected_catch_alls: defaults.length
      )
    end

    remove_column :oom_reports, :oom_report_rule_id
    remove_index :oom_reports, :reported_at if index_exists?(:oom_reports, :reported_at)
    remove_column :oom_reports, :reported_at
    remove_column :vpses, :implicit_oom_report_rule_hit_count
    drop_table :oom_report_rules
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'restoring OOM report rules requires the pre-migration database backup'
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
      oom_reports: %i[oom_report_rule_id reported_at],
      vpses: %i[implicit_oom_report_rule_hit_count],
      event_routes: %i[
        grouping_enabled
        group_by
        group_wait_seconds
        group_interval_seconds
      ]
    }
    missing_columns = required_columns.flat_map do |table, columns|
      columns.reject { |column| column_exists?(table, column) }
             .map { |column| "#{table}.#{column}" }
    end
    return if missing_columns.empty?

    raise ActiveRecord::MigrationError,
          "cannot migrate OOM report rules, missing columns: #{missing_columns.join(', ')}"
  end

  def legacy_rules
    select_all(<<~SQL.squish).to_a
      SELECT oom_report_rules.*, vpses.user_id
      FROM oom_report_rules
      INNER JOIN vpses ON vpses.id = oom_report_rules.vps_id
      ORDER BY vpses.user_id, oom_report_rules.id
    SQL
  end

  def default_admin_routes
    select_all(<<~SQL.squish).each_with_object({}) do |row, ret|
      SELECT user_id, notification_receiver_id
      FROM event_routes
      WHERE parent_id IS NULL
        AND label = #{quote(DEFAULT_ADMIN_ROUTE_LABEL)}
        AND event_type IS NULL
        AND event_type_pattern IS NULL
      ORDER BY user_id, position, id
    SQL
      user_id = row.fetch('user_id').to_i
      ret[user_id] ||= row.fetch('notification_receiver_id')&.to_i
    end
  end

  def validate_default_routes!(rules, defaults)
    rule_users = rules.map { |rule| rule.fetch('user_id').to_i }.uniq
    missing = rule_users.reject { |user_id| defaults.has_key?(user_id) }
    missing.concat(defaults.select { |_, receiver_id| receiver_id.nil? }.keys)
    missing.uniq!
    return if missing.empty?

    raise ActiveRecord::MigrationError,
          "cannot migrate OOM report rules, default admin receiver missing for users: #{missing.join(', ')}"
  end

  def effective_oom_receiver_ids(defaults)
    recipients = defaults.dup
    seen = {}

    select_all(<<~SQL.squish).each do |row|
      SELECT user_id, notification_receiver_id
      FROM event_routes
      WHERE parent_id IS NULL
        AND event_type = #{quote(OOM_EVENT_TYPE)}
        AND enabled = 1
        AND notification_receiver_id IS NOT NULL
      ORDER BY user_id, position, id
    SQL
      user_id = row.fetch('user_id').to_i
      recipients[user_id] = row.fetch('notification_receiver_id').to_i unless seen.has_key?(user_id)
      seen[user_id] = true
    end

    recipients
  end

  def implicit_hit_counts
    select_all(<<~SQL.squish).to_h do |row|
      SELECT user_id, SUM(implicit_oom_report_rule_hit_count) AS hit_count
      FROM vpses
      GROUP BY user_id
    SQL
      [row.fetch('user_id').to_i, row.fetch('hit_count').to_i]
    end
  end

  def create_ignored_receivers(rules)
    rules
      .select { |rule| ignore_rule?(rule) }
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
            enabled: 1,
            mute: 1,
            created_at: current_timestamp,
            updated_at: current_timestamp
          )
        ]
      end
  end

  def remove_legacy_oom_recipient_routes!
    route_ids = select_values(<<~SQL.squish).map(&:to_i)
      SELECT id
      FROM event_routes
      WHERE event_type = #{quote(OOM_EVENT_TYPE)}
    SQL
    return if route_ids.empty?

    quoted_ids = route_ids.map { |id| quote(id) }.join(', ')
    execute "DELETE FROM event_route_matchers WHERE event_route_id IN (#{quoted_ids})"
    if table_exists?(:event_route_time_intervals)
      execute "DELETE FROM event_route_time_intervals WHERE event_route_id IN (#{quoted_ids})"
    end
    execute "DELETE FROM event_routes WHERE id IN (#{quoted_ids})"
  end

  def make_room_at_route_start(user_id, count)
    execute <<~SQL.squish
      UPDATE event_routes
      SET position = position + #{quote(count)}
      WHERE user_id = #{quote(user_id)}
        AND parent_id IS NULL
    SQL
  end

  def create_rule_route(rule, user_id:, receiver_id:, position:)
    action = ignore_rule?(rule) ? 'ignore' : 'notify'
    pattern = rule.fetch('cgroup_pattern').to_s
    route_id = create_route(
      user_id:,
      receiver_id:,
      label: "OOM report #{action} #{pattern}"[0, 255],
      position:,
      hit_count: rule.fetch('hit_count').to_i,
      grouping: !ignore_rule?(rule)
    )

    create_matcher(route_id, 'vps_id', '==', rule.fetch('vps_id').to_s)
    create_matcher(route_id, 'cgroup', '=*', pattern)
    route_id
  end

  def create_catch_all_route(user_id:, receiver_id:, position:, hit_count:)
    create_route(
      user_id:,
      receiver_id:,
      label: 'OOM report notifications',
      position:,
      hit_count:,
      grouping: true
    )
  end

  def create_route(user_id:, receiver_id:, label:, position:, hit_count:, grouping:)
    insert_row(
      :event_routes,
      user_id:,
      parent_id: nil,
      notification_receiver_id: receiver_id,
      label:,
      position:,
      enabled: 1,
      event_type: OOM_EVENT_TYPE,
      event_type_pattern: nil,
      template_name: nil,
      grouping_enabled: grouping ? 1 : 0,
      group_by: grouping ? JSON.dump(['vps_id']) : nil,
      group_wait_seconds: grouping ? GROUP_WAIT_SECONDS : nil,
      group_interval_seconds: grouping ? GROUP_INTERVAL_SECONDS : nil,
      continue: 0,
      hit_count:,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
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

  def verify_conversion!(source_count:, route_ids:, catch_all_ids:, expected_catch_alls:)
    unless route_ids.length == source_count
      raise ActiveRecord::MigrationError,
            "expected #{source_count} migrated OOM report rule routes, created #{route_ids.length}"
    end
    unless catch_all_ids.length == expected_catch_alls
      raise ActiveRecord::MigrationError,
            "expected #{expected_catch_alls} OOM catch-all routes, created #{catch_all_ids.length}"
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
    return if matcher_count == source_count * 2

    raise ActiveRecord::MigrationError,
          "expected #{source_count * 2} migrated OOM report matchers, created #{matcher_count}"
  end

  def ignore_rule?(rule)
    rule.fetch('action').to_i == 1
  end

  def insert_row(table, attrs)
    columns = attrs.keys.map { |name| quote_column_name(name) }.join(', ')
    values = attrs.values.map { |value| connection.quote(value) }.join(', ')

    execute <<~SQL.squish
      INSERT INTO #{quote_table_name(table)} (#{columns})
      VALUES (#{values})
    SQL

    select_value('SELECT LAST_INSERT_ID()').to_i
  end

  def select_all(sql)
    connection.select_all(sql)
  end

  def select_values(sql)
    connection.select_values(sql)
  end

  def current_timestamp
    @current_timestamp ||= Time.now.utc.strftime('%Y-%m-%d %H:%M:%S.%6N')
  end
end
