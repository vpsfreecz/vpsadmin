class CommandFailed < StandardError
	attr_reader :cmd, :rc, :output
	
	def initialize(cmd, rc, out)
		@cmd = cmd
		@rc = rc
		@output = out
	end
	
	def message
		"command '#{@cmd}' exited with code '#{@rc}', output: '#{@output}'"
	end
end

class CommandNotImplemented < StandardError
	
end

class Executor
	attr_accessor :output
	
	def initialize(veid = nil, params = {}, command = nil, daemon = nil)
		@veid = veid
		@params = params
		@output = {}
		@command = command
		@daemon = daemon
		@m_attr = Mutex.new
	end
	
	def attrs
		@m_attr.synchronize do
			yield
		end
	end
	
	def step
		attrs do
			@step
		end
	end
	
	def subtask
		attrs do
			@subtask
		end
	end
	
	def zfs?
		[:zfs, :zfs_compat].include?($CFG.get(:vpsadmin, :fstype))
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
		
		syscmd("#{$CFG.get(:vz, :vzctl)} #{cmd} #{veid} #{options.join(" ")} #{"--save" if save}", valid_rcs)
	end
	
	def scp(what, where, opts = nil)
		syscmd("#{$CFG.get(:bin, :scp)} #{opts} #{what} #{where}")
	end
	
	def rsync(cfg, vars, rcs = [23, 24])
		cmd = $CFG.get(*cfg)
		vars[:rsync] ||= $CFG.get(:bin, :rsync)
		
		vars.each do |k, v|
			cmd = cmd.gsub(/%\{#{k}\}/, v)
		end
		
		syscmd(cmd, rcs)
	end
	
	def syscmd(cmd, valid_rcs = [])
		set_step(cmd)
		
		out = ""
		log "Exec #{cmd}"
		
		IO.popen("exec #{cmd} 2>&1") do |io|
			attrs do
				@subtask = io.pid
			end
			
			out = io.read
		end
		
		attrs do
			@subtask = nil
		end
		
		if $?.exitstatus != 0 and not valid_rcs.include?($?.exitstatus)
			raise CommandFailed.new(cmd, $?.exitstatus, out)
		end
		
		{:ret => :ok, :output => out, :exitstatus => $?.exitstatus}
	end
	
	def post_save(con)
		
	end
	
	def ok
		{:ret => :ok}
	end
	
	private
	
	def set_step(str)
		attrs do
			@step = str
		end
	end
end
