module VpsAdmind
  class Db
    include Utils::Log

    def initialize(db = nil)
      db ||= $CFG.get(:db)

      connect(db)
    end

    def query(q)
      protect do
        @my.query(q)
      end
    end

    def prepared(q, *params)
      prepared_st(q, *params).close
    end

    def prepared_st(q, *params)
      protect do
        st = @my.prepare(q)
        st.execute(*params)
        st
      end
    end

    def insert_id
      @my.insert_id
    end

    def transaction(kwargs = {})
      restart = kwargs.has_key?(:restart) ? kwargs[:restart] : true
      wait = kwargs[:wait]
      tries = kwargs[:tries] || 10
      counter = 0
      try_restart = true

      begin
        log(:info, :sql, "Retrying transaction, attempt ##{counter}") if counter > 0
        @my.query('BEGIN')
        yield(DbTransaction.new(@my))
        @my.query('COMMIT')

      rescue RequestRollback
        log(:info, :sql, 'Rollback requested')
        query('ROLLBACK')

      rescue Mysql::Error => err
        query('ROLLBACK')

        case err.errno
        when 1213
          log(:warn, :sql, 'Deadlock found')

        when 2006
          log(:warn, :sql, 'Lost connection to MySQL server during query')

        when 2013
          log(:warn, :sql, 'MySQL server has gone away')

        else
          try_restart = false
        end
        
        if restart && try_restart
          counter += 1

          if counter <= tries
            w = wait || (counter * 5 + rand(15))
            log(:warn, :sql, "Restarting transaction in #{w} seconds")
            sleep(w)
            retry

          else
            log(:critical, :sql, 'All attempts to restart the transaction failed')
          end
        end

        log(:critical, :sql, 'MySQL transactions failed due to database error, rolling back')
        p err.inspect
        p err.traceback if err.respond_to?(:traceback)
        raise err

      rescue => err
        log(:critical, :sql, 'MySQL transactions failed, rolling back')
        p err.inspect
        p err.traceback if err.respond_to?(:traceback)
        query('ROLLBACK')
        raise err
      end
    end

    def union
      u = Union.new(self)
      yield(u)
      u
    end

    def close
      @my.close
    end

    private

    def connect(db)
      if !db[:host].nil? && db[:hosts].empty?
        db[:hosts] << db[:host]
      end

      problem = false

      loop do
        db[:hosts].each do |host|
          begin
            log(:info, :sql, "Trying to connect to #{host}") if problem
            @my = Mysql.init
            @my.ssl_set if db[:ssl]
            @my.options(Mysql::OPT_CONNECT_TIMEOUT, db[:connect_timeout])
            @my.options(Mysql::OPT_READ_TIMEOUT, db[:read_timeout])
            @my.options(Mysql::OPT_WRITE_TIMEOUT, db[:write_timeout])
            @my.connect(host, db[:user], db[:pass], db[:name])
            query('SET NAMES UTF8')
            log(:info, :sql, "Connected to #{host}") if problem
            return

          rescue Mysql::Error => err
            problem = true
            log(:warn, :sql, "MySQL error ##{err.errno}: #{err.error}")
            log(:info, :sql, 'Trying another host')
          end

          interval = $CFG.get(:db, :retry_interval)
          log(:warn, :sql, "All hosts failed, next try in #{interval} seconds")
          sleep(interval)
        end
      end
    end

    def protect(try_again = true)
      begin
        yield
      rescue Mysql::Error => err
        log(:critical, :sql, "MySQL error ##{err.errno}: #{err.error}")
        close if @my
        sleep($CFG.get(:db, :retry_interval))
        connect($CFG.get(:db))
        retry if try_again
      end
    end
  end

  class DbTransaction < Db
    def initialize(my)
      @my = my
    end

    def protect(try_again = true)
      begin
        yield
      rescue Mysql::Error => err
        log(:critical, :sql, "MySQL error ##{err.errno}: #{err.error}")
        raise err
      end
    end

    def rollback
      raise RequestRollback
    end
  end

  class Union
    def initialize(db)
      @db = db
      @results = []
    end

    def query(*args)
      @results << @db.query(*args)
    end

    def each_hash
      @results.each do |r|
        r.each_hash do |row|
          yield(row)
        end
      end
    end
  end

  class RequestRollback < StandardError

  end
end
