require 'json'
require 'libosctl'
require 'nodectld/exceptions'
require 'nodectld/utils'
require 'thread'

module NodeCtld
  class Command
    include OsCtl::Lib::Utils::Log

    class << self
      def register(type, klass)
        @handlers ||= {}
        @handlers[type] = klass
      end

      def handler(type)
        @handlers[type]
      end
    end

    attr_reader :transaction_id, :command_id, :handle, :handler, :method,
      :time_start

    def initialize(t_id, cmd_id, handle, input)
      @transaction_id = t_id
      @command_id = cmd_id
      @handle = handle
      @handler = NodeCtld::Command.handler(handle)
      @input = input
      @m_attr = Mutex.new

      unless @handler
        raise CommandFailed, 'Unsupported command'
      end
    end

    def execute(method)
      @method = method
      @cmd = @handler.new(self, @input)
      safe_call(@cmd, method)
    end

    def step
      @cmd && @cmd.step
    end

    def subtask
      @cmd && @cmd.subtask
    end

    def progress
      @m_attr.synchronize { @progress && @progress.clone }
    end

    def progress=(v)
      @m_attr.synchronize { @progress = v }
    end

    def log_type
      "trans=#{transaction_id},cmd=#{command_id},type=#{method}"
    end

    protected
    def safe_call(cmd, method)
      @time_start = Time.now

      ret =
        case method
        when 'execute'
          cmd.exec
        when 'rollback'
          cmd.rollback
        else
          raise CommandFailed, 'Unsupported action'
        end

      if !ret.is_a?(Hash) || !ret.has_key?(:ret)
        raise CommandFailed, 'Invalid return value'
      end

      ret[:output] || {}

    rescue SystemCommandFailed => e
      raise CommandFailed, {
        cmd: e.cmd,
        exitstatus: e.rc,
        error: e.output,
      }

    rescue CommandNotImplemented
      raise CommandFailed, 'Command not implemented'

    rescue => e
      raise CommandFailed, {
        error: e.inspect,
        backtrace: e.backtrace,
      }
    end
  end
end
