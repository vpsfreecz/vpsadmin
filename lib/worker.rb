class Worker
	attr_reader :done
	
	def initialize(cmd)
		@queue = Queue.new
		@queue << cmd
		@done = Queue.new
		work
	end
	
	def <<(cmd)
		@queue << cmd
		
		work unless self.working?
	end
	
	def work
		if self.working?
			return nil
		end
		
		@thread = Thread.new do
			until @queue.empty?
				cmd = @queue.pop
				cmd.execute
				@done << cmd
			end
		end
	end
	
	def working?
		@thread and @thread.alive?
	end
end
