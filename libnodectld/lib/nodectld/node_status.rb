require 'ostruct'
require 'nodectld/db'
require 'nodectld/exceptions'
require 'nodectld/system_probes'

module NodeCtld
  class NodeStatus
    def initialize(pool_status)
      @pool_status = pool_status
      @cpu_usage = SystemProbes::CpuUsage.new
      @cpu_usage.start
      @kernel_host = hypervisor? || storage?
      @security_evidence = SystemProbes::SecurityEvidence.new if @kernel_host

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    def update
      t = Time.now.utc

      pool_check, pool_state, pool_scan, pool_scan_percent = @pool_status.summary_values

      mem = SystemProbes::Memory.new
      cpus = SystemProbes::Cpus.new.count
      arc = SystemProbes::Arc.new if @kernel_host
      uptime = SystemProbes::Uptime.new.uptime.round
      kernel = SystemProbes::Kernel.new.version if @kernel_host

      status = {
        id: $CFG.get(:vpsadmin, :node_id),
        time: t.to_i,
        vpsadmin_version: NodeCtld::VERSION,
        kernel:,
        cgroup_version:,
        nproc: 0,
        uptime:,
        cpus:,
        cpu: @cpu_usage.values,
        memory: { # in kB
          total: mem.total,
          used: mem.used
        },
        swap: { # in kB
          total: mem.swap_total,
          used: mem.swap_used
        },
        arc: arc && { # in bytes
          c_max: arc.c_max,
          c: arc.c,
          size: arc.size,
          hitpercent: arc.hit_percent
        },
        loadavg: SystemProbes::LoadAvg.new.avg,
        storage: {
          state: pool_state,
          scan: pool_scan,
          scan_percent: pool_scan_percent,
          checked_at: pool_check.to_i
        }
      }

      if @security_evidence
        status[:security_evidence] = @security_evidence.values(
          now: t,
          uptime:,
          reported_release: kernel
        )
      end

      published = NodeBunny.publish_drop(
        @exchange,
        status.to_json,
        content_type: 'application/json',
        routing_key: 'statuses'
      )
      @security_evidence&.report_published if published
    rescue SystemCommandFailed => e
      log(:fatal, :node_status, e.message)
    end

    protected

    def hypervisor?
      $CFG.get(:vpsadmin, :type) == :node
    end

    def storage?
      $CFG.get(:vpsadmin, :type) == :storage
    end

    def cgroup_version
      path = '/run/osctl/cgroup.version'

      begin
        File.read(path).strip.to_i
      rescue SystemCallError => e
        log(:info, "Unable to read cgroup version from #{path}: #{e.message} (#{e.class})") unless $CFG.minimal?

        0
      end
    end
  end
end
