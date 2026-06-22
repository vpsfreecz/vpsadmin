class ConvertNotificationActionColumnsToStrings < ActiveRecord::Migration[8.1]
  ACTION_COLUMNS = {
    notification_receiver_actions: :action,
    event_deliveries: :action,
    event_delivery_attempts: :action
  }.freeze

  INTEGER_TO_STRING_ACTIONS = {
    '0' => 'email',
    '1' => 'webhook',
    '2' => 'telegram'
  }.freeze

  STRING_TO_INTEGER_ACTIONS = INTEGER_TO_STRING_ACTIONS.invert.freeze

  def up
    ACTION_COLUMNS.each do |table, column|
      next unless integer_column?(table, column)

      change_column table, column, :string, null: false, limit: 50
      replace_action_values(table, column, INTEGER_TO_STRING_ACTIONS)
    end
  end

  def down
    ACTION_COLUMNS.each do |table, column|
      next unless string_column?(table, column)

      assert_known_string_actions!(table, column)
      replace_action_values(table, column, STRING_TO_INTEGER_ACTIONS)
      change_column table, column, :integer, null: false
    end
  end

  protected

  def integer_column?(table, column)
    column_type(table, column) == :integer
  end

  def string_column?(table, column)
    column_type(table, column) == :string
  end

  def column_type(table, column)
    connection.columns(table).find { |c| c.name == column.to_s }&.type
  end

  def replace_action_values(table, column, mapping)
    mapping.each do |from, to|
      execute <<~SQL.squish
        UPDATE #{quote_table_name(table)}
        SET #{quote_column_name(column)} = #{quote(to)}
        WHERE #{quote_column_name(column)} = #{quote(from)}
      SQL
    end
  end

  def assert_known_string_actions!(table, column)
    values = select_values <<~SQL.squish
      SELECT DISTINCT #{quote_column_name(column)}
      FROM #{quote_table_name(table)}
      WHERE #{quote_column_name(column)} NOT IN
        (#{STRING_TO_INTEGER_ACTIONS.keys.map { |v| quote(v) }.join(', ')})
    SQL

    return if values.empty?

    raise ActiveRecord::IrreversibleMigration,
          "cannot convert #{table}.#{column}: unknown actions #{values.inspect}"
  end
end
