class CommandFailed < StandardError
	attr_reader :cmd, :rc, :output
	
	def initialize(cmd, rc, out)
		@cmd = cmd
		@rc = rc
		@output = out
	end
end

class Executor
	attr_accessor :output
	
	def initialize(veid, params = {})
		@veid = veid
		@params = params
		@output = {}
	end
	
	def vzctl(cmd, veid, opts = {}, save = false, valid_rcs = [])
		options = []
		
		if opts.instance_of?(Hash)
			opts.each do |k, v|
				k = k.to_s
				v.each do |s|
					options << "#{k.start_with?("-") ? "" : "--"}#{k} #{s}"
				end
			end
		else
			options << opts
		end
		
		syscmd("#{Settings::VZCTL} #{cmd} #{veid} #{options.join(" ")} #{"--save" if save}", valid_rcs)
	end
	
	def syscmd(cmd, valid_rcs = [])
		out = ""
		puts "Executing: #{cmd}"
		IO.popen("#{cmd} 2>&1") do |io|
			out = io.read
		end
		
		if $?.exitstatus != 0 and not valid_rcs.include?($?.exitstatus)
			raise CommandFailed.new(cmd, $?.exitstatus, out)
		end
		
		{:ret => :ok, :output => out}
	end
	
	def post_save(con)
		
	end
end
