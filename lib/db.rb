require 'rubygems'
require 'mysql'

class Db
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

  def transaction
    begin
      @my.query('BEGIN')
      yield(DbTransaction.new(@my))
      @my.query('COMMIT')
    rescue => err
      puts 'MySQL transactions failed, rolling back'
      p err.inspect
      @my.query('ROLLBACK')
    end
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
          log "Trying to connect to #{host}" if problem
          @my = Mysql.init
          @my.ssl_set
          @my.connect(host, db[:user], db[:pass], db[:name])
          @my.reconnect = true
          log "Connected to #{host}" if problem
          return
        rescue Mysql::Error => err
          problem = true
          log "MySQL error ##{err.errno}: #{err.error}"
          log 'Trying another host'
        end

        interval = $CFG.get(:db, :retry_interval)
        log "All hosts failed, next try in #{interval} seconds"
        sleep(interval)
      end
    end
  end

  def protect(try_again = true)
    begin
      yield
    rescue Mysql::Error => err
      log "MySQL error ##{err.errno}: #{err.error}"
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
      puts "MySQL error ##{err.errno}: #{err.error}"
      raise err
    end
  end
end
