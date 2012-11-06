require 'rubygems'
require 'mysql'

class Db
	def initialize
		connect
	end
	
	def query(q)
		protect do
			@my.query(q)
		end
	end
	
	def prepared(q, *params)
		protect do
			st = @my.prepare(q)
			st.execute(*params)
			st.close
		end
	end
	
	def close
		@my.close
	end
	
	private
	
	def connect
		protect do
			@my = Mysql.new(Settings::DB_HOST, Settings::DB_USER, Settings::DB_PASS, Settings::DB_NAME)
		end
	end
	
	def protect(try_again = true)
		begin
			yield
		rescue Mysql::Error => err
			puts "MySQL error ##{err.errno}: #{err.error}"
			close
			sleep(Settings::DB_RETRY_INTERVAL)
			connect
			retry if try_again
		end
	end
end
