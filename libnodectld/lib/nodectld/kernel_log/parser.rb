require 'libosctl'
require 'thread'

module NodeCtld
  # Read from kernel log and parse recognized events
  class KernelLog::Parser
    include OsCtl::Lib::Utils::Log

    def initialize(file: '/dev/kmsg')
      @file = file
      @queue = Queue.new
      @stop = false
      @event = nil
    end

    # Initiate reading from the kernel log
    def start
      @reader = Thread.new { read_thread }
      @parser = Thread.new do
        begin
          parse_thread
        rescue => e
          log(:warn, "Parser aborted with #{e.class}: #{e.message}")
          sleep(5)
          queue.clear
          retry unless @stop
        end
      end
      nil
    end

    # Stop reading from the kernel log
    def stop
      @stop = true
      @reader.join
      @parser.join
      nil
    end

    def log_type
      'kmsg-parser'
    end

    protected
    attr_reader :file, :queue, :stop, :event

    def read_thread
      log(:info, "Reading from #{file}")

      io = File.open(file, 'r')
      io.seek(0, IO::SEEK_END)

      loop do
        if stop
          queue << :stop
          break
        end

        begin
          line = io.readline
        rescue Errno::EPIPE
          line = :hole
        end

        queue << [line, Time.now]

        size = queue.size
        log(:warn, "Parser queue size at #{size} lines") if size > 100
      end

      io.close
    end

    def parse_thread
      log(:info, 'Starting kernel log parser')

      last_seq = nil
      hole = false
      lost_msgs = 0

      loop do
        line, time = queue.pop

        if line == :hole
          hole = true
          next
        elsif line == :stop
          break
        end

        msg = KernelLog::Message.new(line, time)

        if hole && msg.continuation?
          # Skip unfinished continuation lines
          next
        end

        missed_msgs = last_seq ? msg.seq - last_seq : 0
        last_seq = msg.seq

        if event
          if hole
            hole = false

            call_event do
              event.lost_messages(missed_msgs)
            end
          end

          if event
            call_event do
              event << msg
            end

            next
          end
        end

        hole = false

        if KernelLog::OomKill::Event.start?(msg)
          @event = KernelLog::OomKill::Event.new

          call_event do
            event.start(msg)
          end
        end
      end
    end

    def call_event
      begin
        yield
      rescue KernelLog::Event::Error
        close_event
      else
        close_event if event.finished?
      end
    end

    def close_event
      event.close
      @event = nil
    end
  end
end
