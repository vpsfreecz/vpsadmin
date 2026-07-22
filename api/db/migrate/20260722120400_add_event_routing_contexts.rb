class AddEventRoutingContexts < ActiveRecord::Migration[8.1]
  def up
    add_column :event_routes, :subject_scope, :integer, null: false, default: 0
    add_index :event_routes, %i[subject_scope enabled],
              name: 'index_event_routes_on_subject_scope_enabled'

    create_table :event_routing_contexts do |t|
      t.references :event, null: false
      t.references :user, null: false
      t.string :subject_relation, null: false, limit: 50
      t.string :source, null: false, limit: 50
      t.integer :routing_state, null: false
      t.bigint :matched_event_route_id, null: true
      t.timestamps null: false
    end

    add_index :event_routing_contexts, %i[event_id user_id],
              unique: true,
              name: 'index_event_routing_contexts_on_event_user'
    add_index :event_routing_contexts, :routing_state
    add_index :event_routing_contexts, :subject_relation
    add_index :event_routing_contexts, :matched_event_route_id,
              name: 'index_event_routing_contexts_on_matched_route'

    add_reference(
      :event_deliveries,
      :event_routing_context,
      null: true,
      index: { name: 'idx_event_deliveries_on_routing_context' }
    )

    backfill_existing_delivery_contexts
  end

  def down
    remove_reference :event_deliveries, :event_routing_context,
                     index: { name: 'idx_event_deliveries_on_routing_context' }

    drop_table :event_routing_contexts

    remove_index :event_routes, name: 'index_event_routes_on_subject_scope_enabled'
    remove_column :event_routes, :subject_scope
  end

  protected

  def backfill_existing_delivery_contexts
    return unless table_exists?(:event_deliveries)
    return unless table_exists?(:events)

    say_with_time('Creating routing contexts for existing event deliveries') do
      select_all(<<~SQL.squish).each do |row|
        SELECT
          event_deliveries.id AS delivery_id,
          event_deliveries.event_id,
          events.user_id AS event_user_id,
          event_routes.user_id AS route_user_id,
          event_deliveries.event_route_id,
          event_deliveries.state,
          events.matched_event_route_id
        FROM event_deliveries
        INNER JOIN events ON events.id = event_deliveries.event_id
        LEFT JOIN event_routes ON event_routes.id = event_deliveries.event_route_id
        WHERE event_deliveries.event_routing_context_id IS NULL
      SQL
        user_id = row.fetch('route_user_id') || row.fetch('event_user_id')
        next if user_id.nil?

        subject_relation =
          if row.fetch('event_user_id').nil?
            'system'
          elsif row.fetch('event_user_id').to_i == user_id.to_i
            'self'
          else
            'other_user'
          end

        context_id = find_or_create_context(
          event_id: row.fetch('event_id'),
          user_id:,
          subject_relation:,
          source: context_source(subject_relation),
          routing_state: delivery_context_state(row.fetch('state')),
          matched_event_route_id: row.fetch('event_route_id') || row.fetch('matched_event_route_id')
        )

        execute <<~SQL.squish
          UPDATE event_deliveries
          SET event_routing_context_id = #{quote(context_id)}
          WHERE id = #{quote(row.fetch('delivery_id'))}
        SQL
      end
    end
  end

  def find_or_create_context(event_id:, user_id:, subject_relation:, source:,
                             routing_state:, matched_event_route_id:)
    existing = select_value(<<~SQL.squish)
      SELECT id
      FROM event_routing_contexts
      WHERE event_id = #{quote(event_id)}
        AND user_id = #{quote(user_id)}
      LIMIT 1
    SQL
    return existing.to_i if existing

    insert_row(
      'event_routing_contexts',
      event_id:,
      user_id:,
      subject_relation:,
      source:,
      routing_state:,
      matched_event_route_id:,
      created_at: current_timestamp,
      updated_at: current_timestamp
    )
  end

  def delivery_context_state(delivery_state)
    case delivery_state.to_i
    when 4, 6
      1
    when 5
      2
    else
      0
    end
  end

  def context_source(subject_relation)
    case subject_relation
    when 'self'
      'direct_route'
    when 'system'
      'system_route'
    else
      'visible_route'
    end
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
