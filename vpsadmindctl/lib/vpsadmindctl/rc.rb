require 'pp'
require 'lib/vpsadmindctl/vpsadmind'
require 'lib/vpsadmindctl/utils'
require 'lib/vpsadmindctl/version'
require 'lib/vpsadmindctl/command'

require 'pry-remote' if RUBY_VERSION >= '2.0'

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
        cmd.post_send
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
