require 'lib/console'

require 'rubygems'
require 'eventmachine'
require 'json'

class RemoteControl < EventMachine::Connection
  @@handlers = {}

  def initialize(daemon)
    @daemon = daemon
  end

  def post_init
    send_data({:version => VpsAdmind::VERSION}.to_json + "\n")
  end

  def receive_data(data)
    begin
      req = JSON.parse(data, :symbolize_names => true)
    rescue TypeError
      return error("Syntax error")
    end

    cmd = @@handlers[req[:command]]

    return error("Unsupported command") unless cmd

    executor = Kernel.const_get(cmd[:class]).new(nil, req[:params], nil, @daemon)
    output = {}

    begin
      ret = executor.method(cmd[:method]).call
    rescue CommandFailed => err
      output[:cmd] = err.cmd
      output[:exitstatus] = err.rc
      output[:error] = err.output
      error(output)
    else
      if ret[:ret] == :ok
        ok(ret[:output])
      else
        error(ret[:output])
      end
    end
  end

  def unbind

  end

  def error(err)
    send_data({:status => :failed, :error => err}.to_json + "\n")
  end

  def ok(res)
    send_data({:status => :ok, :response => res}.to_json + "\n")
  end

  def RemoteControl.load_handlers
    $CFG.get(:remote, :handlers).each do |klass, cmds|
      cmds.each do |cmd|
        @@handlers[cmd] = {:class => klass, :method => cmd}
        log "Remote cmd #{cmd} => #{klass}.#{cmd}"
      end
    end
  end
end
