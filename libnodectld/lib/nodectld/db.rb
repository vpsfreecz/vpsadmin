require 'libosctl'
require 'mysql2'

module NodeCtld
  class Db
    include OsCtl::Lib::Utils::Log

    def self.open
      db = Db.new
      yield(db)
      db.close
    end

    def initialize(db = nil)
      db ||= $CFG.get(:db)

      connect(db)
    end

    def query(q)
      protect do
        Result.new(@my.query(q))
      end
    end

    def prepared(q, *params)
      protect do
        st = @my.prepare(q)
        Result.new(st.execute(*params))
      end
    end

    def insert_id
      @my.last_id
    end

    def transaction(kwargs = {})
      restart = kwargs.has_key?(:restart) ? kwargs[:restart] : true
      wait = kwargs[:wait]
      tries = kwargs[:tries]
      counter = 0
      try_restart = true

      begin
        log(:info, :sql, "Retrying transaction, attempt ##{counter}") if counter > 0
        connect($CFG.get(:db)) if @my.closed?
        @my.query('BEGIN')
        yield(DbTransaction.new(@my))
        @my.query('COMMIT')
      rescue RequestRollback
        log(:info, :sql, 'Rollback requested')
        query('ROLLBACK')
      rescue Mysql2::Error => e
        query('ROLLBACK')

        if e.message == 'MySQL client is not connected'
          log(:warn, :sql, 'MySQL client is not connected')
        else
          case e.errno
          when 1213
            log(:warn, :sql, 'Deadlock found')

          when 2000
            log(:warn, :sql, 'Unknown error')
            @my.close

          when 2006
            log(:warn, :sql, 'Lost connection to MySQL server during query')

          when 2013
            log(:warn, :sql, 'MySQL server has gone away')

          when 2014
            log(:warn, :sql, 'Commands out of sync')
            @my.close

          else
            try_restart = false
          end
        end

        if restart && try_restart
          counter += 1

          if tries.nil? || tries == 0 || counter <= tries
            w = wait || ((counter * 5) + rand(15))
            w = 10 * 60 if w > 10 * 60
            log(:warn, :sql, "Restarting transaction in #{w} seconds")
            sleep(w)
            retry

          else
            log(:critical, :sql, 'All attempts to restart the transaction failed')
          end
        end

        log(:critical, :sql, 'MySQL transactions failed due to database error, rolling back')
        p e.inspect
        p e.traceback if e.respond_to?(:traceback)
        raise e
      rescue StandardError => e
        log(:critical, :sql, 'MySQL transactions failed, rolling back')
        p e.inspect
        p e.traceback if e.respond_to?(:traceback)
        query('ROLLBACK')
        raise e
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
      db[:hosts] << db[:host] if !db[:host].nil? && db[:hosts].empty?

      problem = false

      loop do
        db[:hosts].each do |host|
          begin
            log(:info, :sql, "Trying to connect to #{host}") if problem
            @my = Mysql2::Client.new(
              host:,
              username: db[:user],
              password: db[:pass],
              database: db[:name],
              encoding: 'utf8',
              connect_timeout: db[:connect_timeout],
              read_timeout: db[:read_timeout],
              write_timeout: db[:write_timeout],
              database_timezone: :utc
            )
            query('SET NAMES UTF8')
            log(:info, :sql, "Connected to #{host}") if problem
            return # rubocop:disable Lint/NonLocalExitFromIterator
          rescue Mysql2::Error => e
            problem = true
            log(:warn, :sql, "MySQL error ##{e.errno}: #{e.error}")
            log(:info, :sql, 'Trying another host')
          end

          interval = $CFG.get(:db, :retry_interval)
          log(:warn, :sql, "All hosts failed, next try in #{interval} seconds")
          sleep(interval)
        end
      end
    end

    def protect(try_again = true)
      yield
    rescue Mysql2::Error => e
      log(:critical, :sql, "MySQL error ##{e.errno}: #{e.error}")
      close if @my
      sleep($CFG.get(:db, :retry_interval))
      connect($CFG.get(:db))
      retry if try_again
    rescue Errno::EBADF
      log(:critical, :sql, 'Errno::EBADF raised, reconnecting')
      close if @my
      sleep(1)
      connect($CFG.get(:db))
      retry if try_again
    end
  end

  class DbTransaction < Db
    def initialize(my) # rubocop:disable Lint/MissingSuper
      @my = my
    end

    def protect(_try_again = true)
      yield
    rescue Mysql2::Error => e
      log(:critical, :sql, "MySQL error ##{e.errno}: #{e.error}")
      raise e
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

    def query(*)
      @results << @db.query(*)
    end

    def each(&block)
      @results.each do |r|
        next unless r.valid?

        r.each(&block)
      end
    end
  end

  class Result
    # @param result [Mysql2::Result]
    def initialize(result)
      @result = result
    end

    def valid?
      !@result.nil?
    end

    def each(&)
      @result.each(&)
    end

    def get
      @result.each { |row| return row } # rubocop:disable Lint/UnreachableLoop
      nil
    end

    def get!
      get || (raise 'no row returned')
    end

    def count
      @result.count
    end
  end

  class RequestRollback < StandardError; end
end
