require 'libosctl'
require 'singleton'

module NodeCtld
  # Submit OOM reports to database for processing
  #
  # Containers can generate hundreds/thousands OOM events per second, This class
  # performs rate-limiting by aggregating identical reports. There are two
  # scenarios which usually cause duplicit reports:
  #
  #   1) Some program uses all available memory in its cgroup and further
  #      allocations cause OOM report, although nothing is ever killed. This is
  #      usually an infinite loop causing many reports per second. We consider
  #      reports identical when {KernelLog::OomKill::Report#invoked_by_name} is
  #      the same.
  #
  #   2) Some program gets started, hits memory limit and is killed in a loop.
  #      We considers reports identical when {KernelLog::OomKill::Report#killed_name}
  #      is the same.
  #
  # We save one unique report per VPS per minute by default, duplicit events are
  # aggregated.
  class KernelLog::OomKill::Submitter
    include Singleton
    include OsCtl::Lib::Utils::Log

    class << self
      %i[<<].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      @queue = OsCtl::Lib::Queue.new
      @mutex = Mutex.new
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @input_thread = Thread.new { process_queue }
      @save_thread = Thread.new { save_reports }
      @vps_reports = {}
    end

    # Add report for submission
    # @param report [KernelLog::OomKill::Report]
    def <<(report)
      @queue << report
    end

    def log_type
      'oom-submitter'
    end

    protected

    def process_queue
      loop do
        add_report(@queue.pop)
      end
    end

    def save_reports
      loop do
        sleep($CFG.get(:oom_reports, :submit_interval))

        vps_reports = nil

        @mutex.synchronize do
          vps_reports = @vps_reports.clone
          @vps_reports.clear
        end

        next if vps_reports.empty?

        vps_reports.each_value do |reports|
          reports.each do |r|
            log(:info, "Submitting OOM report invoked by PID #{r.invoked_by_pid} from VPS #{r.vps_id}")
            NodeBunny.publish_wait(
              @exchange,
              r.export.to_json,
              content_type: 'application/json',
              routing_key: 'oom_reports'
            )
          end
        end
      end
    end

    def add_report(report)
      @mutex.synchronize do
        reports = @vps_reports.fetch(report.vps_id, [])

        existing_report =
          if report.no_killable
            reports.detect do |r|
              r.no_killable \
                && r.cgroup == report.cgroup \
                && r.invoked_by_name == report.invoked_by_name
            end

          else # a process was killed
            reports.detect do |r|
              r.killed_pid \
                && r.cgroup == report.cgroup \
                && r.killed_name == report.killed_name
            end
          end

        if existing_report
          existing_report.count += 1
        else
          report.find_vps_pids_and_uids
          reports << report
        end

        @vps_reports[report.vps_id] = reports
      end
    end
  end
end
