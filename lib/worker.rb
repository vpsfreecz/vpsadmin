class Worker
	attr_reader :cmd
	
	def initialize(cmd)
		@cmd = cmd
		work
	end
	
	def work
		if self.working?
			return nil
		end
		
		@thread = Thread.new do
			@cmd.execute
		end
	end
	
	def kill
		cmd.killed
		@thread.kill!
	end
	
	def working?
		@thread and @thread.alive?
	end
end
