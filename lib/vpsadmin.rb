require 'lib/executor'
require 'lib/daemon'

class VpsAdmin < Executor
	def stop
		VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_STOP)
		ok
	end
	
	def restart
		VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_RESTART)
		ok
	end
	
	def update
		VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_UPDATE)
		ok
	end
end
