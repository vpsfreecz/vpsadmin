require 'pp'
require 'lib/vpsadmind'
require 'lib/utils'
require 'lib/version'
require 'lib/command'

module VpsAdmindCtl
	class RemoteControl
		def initialize(options)
			@global_opts = options
			@vpsadmind = VpsAdmind.new(options[:sock])
		end
		
		def exec(cmd)
      cmd.set_args(ARGV[0..-1])
      cmd.set_global_options(@global_opts)
      cmd.vpsadmind(@vpsadmind)

      begin
        params = cmd.validate
      rescue ValidationError => err
        warn 'Command failed'
        warn "#{cmd.cmd}: #{err.message}"
        return
      rescue => err
        warn 'Command failed'
        warn err.inspect
        return
      end

      params ||= cmd.prepare

			begin
				@vpsadmind.open
				@vpsadmind.cmd(cmd.cmd, params)
				@reply = @vpsadmind.reply
			rescue
        warn "Error occured: #{$!}"
        warn 'Are you sure that vpsAdmind is running and configured properly?'
				return {:status => :failed, :error => 'Cannot connect to vpsAdmind'}
			end

			unless @reply[:status] == 'ok'
				return {
          :status => :failed,
          :error => @reply[:error].instance_of?(Hash) ? @reply[:error][:error] : @reply[:error],
        }
			end

      cmd.response(@reply[:response])
			cmd.process
		end
	end
end
