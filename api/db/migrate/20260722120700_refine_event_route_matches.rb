class RefineEventRouteMatches < ActiveRecord::Migration[8.1]
  DEFAULT_EMAIL_LABEL = 'Default'.freeze
  LEGACY_DEFAULT_EMAIL_LABEL = 'Default e-mail'.freeze
  DEFAULT_EMAIL_DESCRIPTION = 'Default notification receiver'.freeze
  LEGACY_DEFAULT_EMAIL_DESCRIPTION = 'Created from the existing mailer setting'.freeze

  def up
    create_event_route_matches
    backfill_event_route_matches
    remove_legacy_matched_route_columns
    normalize_default_email_labels
  end

  def down
    restore_legacy_matched_route_columns
    denormalize_default_email_labels
    drop_table :event_route_matches if table_exists?(:event_route_matches)
  end

  protected

  def create_event_route_matches
    return if table_exists?(:event_route_matches)

    create_table :event_route_matches do |t|
      t.references :event, null: false
      t.references :event_route, null: false
      t.bigint :route_owner_id, null: false
      t.string :subject_relation, null: false, limit: 32
      t.string :source, null: false, limit: 32
      t.integer :match_order, null: false, default: 0
      t.timestamps null: false
    end

    add_index :event_route_matches, %i[event_id match_order id],
              name: 'idx_event_route_matches_on_event_order'
    add_index :event_route_matches, %i[event_route_id event_id],
              name: 'idx_event_route_matches_on_route_event'
    add_index :event_route_matches, :route_owner_id
    add_index :event_route_matches, %i[event_id event_route_id route_owner_id],
              unique: true, name: 'idx_event_route_matches_unique'
  end

  def backfill_event_route_matches
    return unless table_exists?(:event_route_matches)
    return unless table_exists?(:event_routes)

    backfill_from_routing_contexts
    backfill_from_events
  end

  def backfill_from_routing_contexts
    return unless table_exists?(:event_routing_contexts)
    return unless column_exists?(:event_routing_contexts, :matched_event_route_id)

    execute <<~SQL.squish
      INSERT IGNORE INTO event_route_matches
        (event_id, event_route_id, route_owner_id, subject_relation, source,
         match_order, created_at, updated_at)
      SELECT
        event_routing_contexts.event_id,
        event_routing_contexts.matched_event_route_id,
        event_routing_contexts.user_id,
        event_routing_contexts.subject_relation,
        event_routing_contexts.source,
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM event_routing_contexts
      INNER JOIN event_routes
        ON event_routes.id = event_routing_contexts.matched_event_route_id
      WHERE event_routing_contexts.matched_event_route_id IS NOT NULL
    SQL
  end

  def backfill_from_events
    return unless table_exists?(:events)
    return unless column_exists?(:events, :matched_event_route_id)

    execute <<~SQL.squish
      INSERT IGNORE INTO event_route_matches
        (event_id, event_route_id, route_owner_id, subject_relation, source,
         match_order, created_at, updated_at)
      SELECT
        events.id,
        events.matched_event_route_id,
        event_routes.user_id,
        CASE
          WHEN events.user_id IS NULL THEN 'system'
          WHEN events.user_id = event_routes.user_id THEN 'self'
          ELSE 'other_user'
        END,
        CASE
          WHEN events.user_id IS NULL THEN 'system_route'
          WHEN events.user_id = event_routes.user_id THEN 'direct_route'
          ELSE 'visible_route'
        END,
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM events
      INNER JOIN event_routes ON event_routes.id = events.matched_event_route_id
      WHERE events.matched_event_route_id IS NOT NULL
    SQL
  end

  def remove_legacy_matched_route_columns
    if table_exists?(:event_routing_contexts) &&
       column_exists?(:event_routing_contexts, :matched_event_route_id)
      if index_exists?(
        :event_routing_contexts,
        :matched_event_route_id,
        name: 'index_event_routing_contexts_on_matched_route'
      )
        remove_index :event_routing_contexts, name: 'index_event_routing_contexts_on_matched_route'
      end
      remove_column :event_routing_contexts, :matched_event_route_id
    end

    return unless table_exists?(:events) && column_exists?(:events, :matched_event_route_id)

    remove_index :events, :matched_event_route_id if index_exists?(:events, [:matched_event_route_id])
    remove_column :events, :matched_event_route_id
  end

  def restore_legacy_matched_route_columns
    if table_exists?(:events) && !column_exists?(:events, :matched_event_route_id)
      add_column :events, :matched_event_route_id, :bigint, null: true
      add_index :events, :matched_event_route_id
    end

    if table_exists?(:event_routing_contexts) &&
       !column_exists?(:event_routing_contexts, :matched_event_route_id)
      add_column :event_routing_contexts, :matched_event_route_id, :bigint, null: true
      add_index :event_routing_contexts, :matched_event_route_id,
                name: 'index_event_routing_contexts_on_matched_route'
    end

    restore_event_matched_routes
    restore_context_matched_routes
  end

  def restore_event_matched_routes
    return unless table_exists?(:event_route_matches)
    return unless table_exists?(:events) && column_exists?(:events, :matched_event_route_id)

    execute <<~SQL.squish
      UPDATE events
      INNER JOIN event_route_matches
        ON event_route_matches.id = (
          SELECT ordered_matches.id
          FROM event_route_matches AS ordered_matches
          WHERE ordered_matches.event_id = events.id
          ORDER BY ordered_matches.match_order, ordered_matches.id
          LIMIT 1
        )
      SET events.matched_event_route_id = event_route_matches.event_route_id
    SQL
  end

  def restore_context_matched_routes
    return unless table_exists?(:event_route_matches)
    return unless table_exists?(:event_routing_contexts)
    return unless column_exists?(:event_routing_contexts, :matched_event_route_id)

    execute <<~SQL.squish
      UPDATE event_routing_contexts
      INNER JOIN event_route_matches
        ON event_route_matches.id = (
          SELECT ordered_matches.id
          FROM event_route_matches AS ordered_matches
          WHERE ordered_matches.event_id = event_routing_contexts.event_id
            AND ordered_matches.route_owner_id = event_routing_contexts.user_id
          ORDER BY ordered_matches.match_order, ordered_matches.id
          LIMIT 1
        )
      SET event_routing_contexts.matched_event_route_id =
        event_route_matches.event_route_id
    SQL
  end

  def normalize_default_email_labels
    if table_exists?(:notification_receivers)
      execute <<~SQL.squish
        UPDATE notification_receivers
        SET label = #{quote(DEFAULT_EMAIL_LABEL)}
        WHERE label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
          AND mute = 0
          AND description IN (
            #{quote(DEFAULT_EMAIL_DESCRIPTION)},
            #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
          )
      SQL
    end

    return unless table_exists?(:notification_targets)

    execute <<~SQL.squish
      UPDATE notification_targets
      SET label = #{quote(DEFAULT_EMAIL_LABEL)}
      WHERE label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
        AND action = 'email'
        AND target_kind = 0
        AND identity_key = 'default'
    SQL
  end

  def denormalize_default_email_labels
    if table_exists?(:notification_receivers)
      execute <<~SQL.squish
        UPDATE notification_receivers
        SET label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
        WHERE label = #{quote(DEFAULT_EMAIL_LABEL)}
          AND mute = 0
          AND description IN (
            #{quote(DEFAULT_EMAIL_DESCRIPTION)},
            #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
          )
      SQL
    end

    return unless table_exists?(:notification_targets)

    execute <<~SQL.squish
      UPDATE notification_targets
      SET label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
      WHERE label = #{quote(DEFAULT_EMAIL_LABEL)}
        AND action = 'email'
        AND target_kind = 0
        AND identity_key = 'default'
    SQL
  end
end
