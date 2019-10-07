require 'etc'
require 'thread'

module NodeCtld
  class ThreadPool
    def initialize(threads = nil)
      @threads = threads || Etc.nprocessors
      @threads = 1 if @threads < 1
      @queue = Queue.new
    end

    def add(&block)
      queue << block
    end

    def run
      (1..threads).map do
        Thread.new { work }
      end.each(&:join)
    end

    protected
    attr_reader :threads, :queue

    def work
      loop do
        begin
          block = queue.pop(true)
        rescue ThreadError
          return
        end

        block.call
      end
    end
  end
end
