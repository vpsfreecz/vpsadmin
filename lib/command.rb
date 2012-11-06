require 'lib/executor'

require 'rubygems'
require 'json'

class Command
	def initialize(trans)
		@trans = trans
		@output = {}
		@status = :failed
	end
	
	def execute
		cmd = Settings::COMMANDS[ @trans["t_type"].to_i ]
		
		unless cmd
			@output[:error] = "Unsupported command"
			return false
		end
		
		@executor = Kernel.const_get(cmd[:class]).new(@trans["t_vps"], JSON.parse(@trans["t_param"]))
		
		begin
			@status = @executor.method(cmd[:method]).call[:ret]
		rescue CommandFailed => err
			@status = :failed
			@output[:cmd] = err.cmd
			@output[:exitstatus] = err.rc
			@output[:error] = err.output
		end
	end
	
	def save(db)
		db.prepared(
			"UPDATE transactions SET t_done=1, t_success=?, t_output=? WHERE t_id=?",
			{:failed => 0, :ok => 1, :warning => 2}[@status], (@executor ? @output.merge(@executor.output) : @output).to_json, @trans["t_id"]
		)
		
		@executor.post_save(db) if @executor
	end
	
	def dependency_failed(db)
		@output[:error] = "Dependency failed"
		@status = :failed
		save(db)
	end
	
	def id
		@trans["t_id"]
	end
	
	def worker_id
		if @trans.has_key?("t_vps")
			@trans["t_vps"]
		else
			0
		end
	end
end
