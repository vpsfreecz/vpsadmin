require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsPostStart
    include Singleton
    include OsCtl::Lib::Utils::Log

    class << self
      %i[run cancel].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    Job = Struct.new(:vps_id, :time)

    def initialize
      @jobs = {}
      @scheduler_thread = Thread.new { run_scheduler }
      @queue = Queue.new
    end

    # @param vps_id [Integer]
    # @param in_seconds [Integer, nil]
    # @param after_uptime [Integer, nil]
    def run(vps_id, in_seconds: nil, after_uptime: nil)
      after_uptime = $CFG.get(:vps_post_start, :after_uptime) if after_uptime.nil?

      if after_uptime && SystemProbes::Uptime.new.uptime < after_uptime
        log(:info, "Skipping post-start updates for VPS #{vps_id} due to low uptime")
        return
      end

      in_seconds ||= $CFG.get(:vps_post_start, :default_schedule_delay)

      @queue << [:add, Job.new(vps_id, Time.now + in_seconds)]

      nil
    end

    # @param vps_id [Integer]
    def cancel(vps_id)
      @queue << [:cancel, vps_id]
      nil
    end

    def stop
      @queue << [:stop]
      @scheduler_thread.join
      nil
    end

    def log_type
      'vps-post-start'
    end

    protected

    def run_scheduler
      loop do
        cmd, v = @queue.pop(timeout: 1)

        if cmd.nil?
          run_jobs
          next
        end

        case cmd
        when :add
          log(:debug, "Scheduled post-start job for VPS #{v.vps_id} at #{v.time}")
          @jobs[v.vps_id] = v
        when :cancel
          if @jobs.has_key?(v)
            log(:debug, "Cancelled post-start job for VPS #{v}")
            @jobs.delete(v)
          end
        when :stop
          break
        end
      end
    end

    def run_jobs
      now = Time.now

      @jobs.delete_if do |vps_id, job|
        if job.time <= now
          log(:debug, "Running post-start job for VPS #{vps_id}")
          Thread.new { post_start(vps_id) }
          true
        else
          false
        end
      end
    end

    def post_start(vps_id)
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_name(vps_id.to_s)
      return if dom.nil? || !dom.active?

      VpsSshHostKeys.update_vps_id(vps_id)
      VpsOsRelease.update_domain(dom)
    end
  end
end
