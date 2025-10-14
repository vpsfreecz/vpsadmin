require 'libosctl'

module NodeCtld
  # Read from kernel log and parse recognized events
  class KernelLog::Parser
    include OsCtl::Lib::Utils::Log

    def initialize(file: '/dev/kmsg')
      @file = file
      @parse_queue = Queue.new
      @submit_queue = Queue.new
      @stop = false
      @event = nil
    end

    # Initiate reading from the kernel log
    def start
      @reader = Thread.new { read_thread }
      @parser = Thread.new do
        parse_thread
      rescue StandardError => e
        log(:warn, "Parser aborted with #{e.class}: #{e.message}")
        sleep(5)
        parse_queue.clear
        retry unless @stop
      end
      @submitter = Thread.new do
        submit_thread
      rescue StandardError => e
        log(:warn, "Submitter aborted with #{e.class}: #{e.message}")
        sleep(5)
        retry unless @stop
      end
      nil
    end

    # Stop reading from the kernel log
    def stop
      @stop = true
      @parse_queue << :stop
      @submit_queue << :stop
      @reader.join
      @parser.join
      @submitter.join
      nil
    end

    def log_type
      'kmsg-parser'
    end

    protected

    attr_reader :file, :parse_queue, :submit_queue, :event

    def read_thread
      log(:info, "Reading from #{file}")

      io = File.open(file, 'r')
      io.seek(0, IO::SEEK_END)

      last_time = Time.now

      loop do
        break if @stop

        begin
          line = io.readline
        rescue Errno::EPIPE
          line = :hole
        end

        t = Time.now
        parse_queue << [line, t]

        next unless last_time + 5 < t

        size = parse_queue.size

        log(:warn, "Parser queue size at #{size} lines") if size > 128

        if size > 16 * 1024
          log(:warn, 'Parser queue too large, resetting')
          parse_queue.clear
        end

        last_time = t
      end

      io.close
    end

    def parse_thread
      log(:info, 'Starting kernel log parser')

      last_seq = nil
      hole = false
      lost_msgs = 0

      loop do
        line, time = parse_queue.pop

        if line == :hole
          hole = true
          next
        elsif line == :stop
          return
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
      end
    end

    def submit_thread
      loop do
        e = submit_queue.pop
        return if e == :stop

        e.close
      end
    end

    def call_event
      yield
    rescue KernelLog::Event::Error => e
      log(:warn, "Parser error: #{e.message}")
      close_event
    else
      close_event if event.finished?
    end

    def close_event
      submit_queue << event
      @event = nil
    end
  end
end
