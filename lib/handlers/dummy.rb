require 'lib/executor'

class Dummy < Executor
	def dummy
		sleep(60)
	end
	
	def dummydummydummy
		dummy
	end
end
