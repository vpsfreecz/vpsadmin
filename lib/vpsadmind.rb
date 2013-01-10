require 'socket'

require 'rubygems'
require 'json'

class VpsAdmind
	attr_reader :version
	
	def initialize(sock)
		@sock_path = sock
	end
	
	def open
		@sock = UNIXSocket.new(@sock_path)
		greetings = reply
		@version = greetings["version"]
	end
	
	def cmd(cmd)
		@sock.send({:command => cmd}.to_json, 0)
	end
	
	def reply
		parse(@sock.recv(4096))
	end
	
	def response
		reply["response"]
	end
	
	def close
		@sock.close
	end
	
	def parse(raw)
		JSON.parse(raw)
	end
end
