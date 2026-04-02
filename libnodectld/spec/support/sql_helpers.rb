# frozen_string_literal: true

module NodeCtldSpec
  module SqlHelpers
    def shared_db
      @shared_db || raise('shared DB wrapper not installed')
    end

    def raw_connection
      ActiveRecord::Base.connection.raw_connection
    end

    def sql_rows(sql, *binds)
      stmt = raw_connection.prepare(sql)
      stmt.execute(*binds).to_a
    ensure
      stmt&.close
    end

    def sql_row(sql, *binds)
      sql_rows(sql, *binds).first
    end

    def sql_value(sql, *binds)
      row = sql_row(sql, *binds)
      row && row.values.first
    end

    def sql_insert(table, attrs)
      cols = attrs.keys.map { |k| "`#{k}`" }.join(', ')
      placeholders = Array.new(attrs.size, '?').join(', ')

      stmt = raw_connection.prepare(
        "INSERT INTO #{table} (#{cols}) VALUES (#{placeholders})"
      )
      stmt.execute(*attrs.values)
      raw_connection.last_id
    ensure
      stmt&.close
    end

    def sql_update(table, attrs, where_sql, *binds)
      cols = attrs.keys.map { |k| "`#{k}` = ?" }.join(', ')

      stmt = raw_connection.prepare(
        "UPDATE #{table} SET #{cols} WHERE #{where_sql}"
      )
      stmt.execute(*attrs.values, *binds)
    ensure
      stmt&.close
    end
  end
end
