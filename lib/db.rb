require 'rubygems'
require 'mysql'

class Db
	def initialize(host = nil)
		host ||= $CFG.get(:db)
		
		connect(host)
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
	
	def close
		@my.close
	end
	
	private
	
	def connect(host)
		protect do
			@my = Mysql.new(host[:host], host[:user], host[:pass], host[:name])
			@my.reconnect = true
		end
	end
	
	def protect(try_again = true)
		begin
			yield
		rescue Mysql::Error => err
			puts "MySQL error ##{err.errno}: #{err.error}"
			close if @my
			sleep($CFG.get(:db, :retry_interval))
			connect($CFG.get(:db))
			retry if try_again
		end
	end
end
