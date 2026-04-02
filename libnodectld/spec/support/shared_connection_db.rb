# frozen_string_literal: true

module NodeCtldSpec
  class MaterializedResult
    def initialize(result)
      @rows = result.to_a
    end

    def valid?
      true
    end

    def each(&)
      @rows.each(&)
    end

    def get
      @rows.first
    end

    def get!
      get || (raise 'no row returned')
    end

    def count
      @rows.count
    end
  end

  # Nodectld must use the same raw mysql client as ActiveRecord or it would not
  # see rows inserted inside the example's outer transaction.
  class SharedConnectionDb
    def initialize(raw_mysql)
      @raw = raw_mysql
      @savepoint_seq = 0
    end

    def query(sql)
      MaterializedResult.new(@raw.query(sql))
    end

    def prepared(sql, *params)
      stmt = @raw.prepare(sql)
      MaterializedResult.new(stmt.execute(*params))
    ensure
      stmt&.close
    end

    def transaction
      @savepoint_seq += 1
      savepoint = "libnodectld_spec_sp_#{@savepoint_seq}"

      @raw.query("SAVEPOINT #{savepoint}")
      yield(NodeCtld::DbTransaction.new(@raw))
      @raw.query("RELEASE SAVEPOINT #{savepoint}")
    rescue NodeCtld::RequestRollback
      @raw.query("ROLLBACK TO SAVEPOINT #{savepoint}")
      @raw.query("RELEASE SAVEPOINT #{savepoint}")
    rescue StandardError
      begin
        @raw.query("ROLLBACK TO SAVEPOINT #{savepoint}")
        @raw.query("RELEASE SAVEPOINT #{savepoint}")
      rescue StandardError
        nil
      end

      raise
    end

    def union
      union = NodeCtld::Union.new(self)
      yield(union)
      union
    end

    def close
      nil
    end

    def insert_id
      @raw.last_id
    end
  end
end
