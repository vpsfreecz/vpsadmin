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
			begin
				until @queue.empty?
					cmd = @queue.pop(true)
					cmd.execute
					@done << cmd
				end
			rescue ThreadError
				
			end
		end
	end
	
	def working?
		@thread and @thread.alive?
	end
	
	def drop_queue
		@queue.clear
	end
end
