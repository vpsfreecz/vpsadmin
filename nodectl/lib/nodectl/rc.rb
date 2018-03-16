require 'pp'
require 'lib/nodectl/nodectld'
require 'lib/nodectl/utils'
require 'lib/nodectl/version'
require 'lib/nodectl/command'

require 'pry-remote' if RUBY_VERSION >= '2.0'

module NodeCtl
  class RemoteControl
    def initialize(options)
      @global_opts = options
      @nodectld = NodeCtld.new(options[:sock])
    end

    def exec(cmd)
      cmd.set_args(ARGV[0..-1])
      cmd.set_global_options(@global_opts)
      cmd.nodectld(@nodectld)

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
        @nodectld.open
        @nodectld.cmd(cmd.cmd, params)
        cmd.post_send
        @reply = @nodectld.reply

      rescue
        warn "Error occured: #{$!}"
        warn 'Are you sure that nodectld is running and configured properly?'
        return {:status => :failed, :error => 'Cannot connect to nodectld'}
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
