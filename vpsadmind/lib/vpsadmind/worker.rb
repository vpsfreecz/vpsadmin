require 'singleton'
require 'thread'

module VpsAdmind
  class Worker
    include Singleton
    include Utils::Log

    class << self
      %i(run list pause resume paused? kill_all kill_by_handle kill_by_id
         empty?).each do |m|
        define_method(m) do |*args, &block|
          instance.send(m, *args, &block)
        end
      end
    end

    def initialize
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @workers = {}
      @paused = false
    end

    def run(cmd, method)
      q = ::Queue.new

      t = Thread.new do
        sync do
          @cond.wait(@mutex) if @paused
        end

        TransactionBlocker.wait(cmd.transaction_id)
        add_worker(t, cmd)

        begin
          q << {status: true, output: cmd.execute(method)}
        rescue CommandFailed => e
          q << {status: false, output: e.error}
        rescue Exception => e
          log(:warn, "Exception occurred during command execution: #{e.message}")
          log(:warn, e.backtrace.join("\n"))
          q << {
            status: false,
            output: {
              error: e.message,
              backtrace: e.backtrace,
            },
          }
        end
      end

      ret = q.pop
      remove_worker(t)

      raise CommandFailed, ret[:output] unless ret[:status]

      t.join
      ret
    end

    def list
      sync { @workers.values }
    end

    def pause
      sync { @paused = true }
    end

    def resume
      sync do
        @paused = false
        @cond.broadcast
      end
    end

    def paused?
      sync { @paused }
    end

    def kill_all
      kill_if { true }
    end

    def kill_by_handle(handle)
      kill_if do |t, cmd|
        cmd.handle == handle
      end
    end

    def kill_by_id(id)
      kill_if do |t, cmd|
        cmd.command_id == id
      end
    end

    def empty?
      sync { @workers.empty? }
    end

    protected
    def add_worker(thread, cmd)
      sync { @workers[thread] = cmd }
    end

    def remove_worker(thread)
      sync { @workers.delete(thread) }
    end

    def kill_if
      cnt = 0

      sync do
        @workers.delete_if do |t, cmd|
          if yield(t, cmd)
            t.terminate
            cnt += 1
            true
          else
            false
          end
        end
      end

      cnt
    end

    def sync(&block)
      @mutex.synchronize(&block)
    end
  end
end
