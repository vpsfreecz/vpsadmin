require 'rubygems'
require 'eventmachine'

class VzConsole < EventMachine::Connection
	attr_accessor :usage
	
	@@consoles = {}
	
	def initialize(veid, listener)
		@veid = veid
		@listeners = [listener,]
		@usage = 1
		
		@@consoles[@veid] = self
	end
	
	def post_init
		send_data "\n"
	end
	
	def receive_data(data)
		@listeners.each do |l|
			l.send_data(data)
		end
	end
	
	def unbind
		puts "console detached with exit status: #{get_status.exitstatus}"
		
		@listeners.each do |l|
			l.failed_to_attach
		end
	end
	
	def register(c)
		@listeners << c
		@usage += 1
	end
	
	def VzConsole.consoles
		@@consoles
	end
end

class VzServer < EventMachine::Connection
	def post_init
		
	end
	
	def receive_data(data)
		unless @veid
			begin
				lines = data.split
				@veid = lines[0].strip.to_i
				
				if VzConsole.consoles.include?(@veid)
					@console = VzConsole.consoles[@veid]
					@console.register(self)
				else
					@console = EventMachine.popen("#{$APP_CONFIG[:vz][:vzctl]} console #{@veid}", VzConsole, @veid, self)
				end
				
				send_data("Welcome to vpsFree.cz Remote Console\r\n")
				data = lines[1..-1].join('\r\n')
			rescue
				return failed_to_attach
			end
		end
		
		return unless data
		
		if data.strip == "detach"
			send_data("See you later!\r\n")
			
			detach
			
			close_connection_after_writing
		else
			VzConsole.consoles[@veid].send_data(data)
		end
	end
	
	def unbind
		detach if !@detached && @console
	end
	
	def failed_to_attach
		send_data("Failed to attach console, sorry.\r\n")
		close_connection_after_writing
	end
	
	def detach
		@detached = true
		
		@console.usage -= 1
			
		if @console.usage == 0
			VzConsole.consoles[@veid].send_data(13.chr)
			VzConsole.consoles[@veid].send_data(27.chr)
			VzConsole.consoles[@veid].send_data(".")
			VzConsole.consoles.delete(@veid) 
		end
	end
end
