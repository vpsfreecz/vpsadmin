require 'singleton'
require 'thread'

module VpsAdmind
  class TransactionBlocker
    include Singleton
    include Utils::Log

    Entry = Struct.new(:mutex, :cond, :pids) do
      def add(pid)
        mutex.synchronize { pids << pid }
      end

      def delete(pid)
        mutex.synchronize do
          pids.delete(pid)
          cond.broadcast if pids.empty?
        end
      end

      def wait
        mutex.synchronize do
          cond.wait(mutex) unless done?
        end
      end

      def kill_all
        mutex.synchronize do
          pids.each do |pid|
            log(:info, "Sending SIGTERM to subprocess #{pid}")
            Process.kill('TERM', pid)
          end

          pids.clear
        end
      end

      def done?
        pids.empty?
      end
    end

    class << self
      %i(add wait list kill_all empty?).each do |m|
        define_method(m) do |*args, &block|
          instance.send(m, *args, &block)
        end
      end
    end

    def initialize
      @mutex = Mutex.new
      @blockers = {}
    end

    def add(trans_id, pid)
      sync do
        blockers[trans_id] ||= Entry.new(Mutex.new, ConditionVariable.new, [])
        blockers[trans_id].add(pid)
      end

      Thread.new do
        log(:info, "Transaction #{trans_id} will wait for subprocess #{pid} to finish")
        Process.wait(pid)
        subprocess_finished(trans_id, pid)
      end

      true
    end

    def list
      sync do
        Hash[blockers.map do |k, v|
          [k, v.pids]
        end]
      end
    end

    def wait(trans_id)
      @mutex.lock

      unless blockers.has_key?(trans_id)
        @mutex.unlock
        return
      end

      blocker = blockers[trans_id]
      @mutex.unlock

      log(:info, "Transaction #{trans_id} is waiting for subprocesses to finish")
      blocker.wait
    end

    def kill_all
      sync do
        blockers.each_value(&:kill_all)
        blockers.clear
      end
    end

    def empty?
      sync { blockers.empty? }
    end

    def log_type
      'transaction_blocker'
    end

    protected
    attr_reader :blockers

    def subprocess_finished(trans_id, pid)
      sync do
        blocker = blockers[trans_id]
        blocker.delete(pid)
        blockers.delete(trans_id) if blocker.done?
      end
    end

    def sync(&block)
      @mutex.synchronize(&block)
    end
  end
end
