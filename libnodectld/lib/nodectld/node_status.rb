require 'ostruct'
require 'nodectld/db'
require 'nodectld/exceptions'
require 'nodectld/system_probes'

module NodeCtld
  class NodeStatus
    def initialize(pool_status)
      @pool_status = pool_status
      @cpus = SystemProbes::Cpus.new.count

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct('node:statuses')
    end

    def update
      t = Time.now.utc

      pool_check, pool_state, pool_scan, pool_scan_percent = @pool_status.summary_values

      mem = SystemProbes::Memory.new
      arc = SystemProbes::Arc.new if hypervisor? || storage?

      status = {
        id: $CFG.get(:vpsadmin, :node_id),
        time: t.to_i,
        vpsadmin_version: NodeCtld::VERSION,
        kernel: SystemProbes::Kernel.new.version,
        cgroup_version: cgroup_version,
        nproc: 0,
        uptime: SystemProbes::Uptime.new.uptime.round,
        cpus: @cpus,
        cpu: SystemProbes::CpuUsage.new.measure.to_percent,
        memory: { # in kB
          total: mem.total,
          used: mem.used,
        },
        swap: { # in kB
          total: mem.swap_total,
          used: mem.swap_used,
        },
        arc: arc && { # in bytes
          c_max: arc.c_max,
          c: arc.c,
          size: arc.size,
          hitpercent: arc.hit_percent,
        },
        loadavg: SystemProbes::LoadAvg.new.avg,
        storage: {
          state: pool_state,
          scan: pool_scan,
          scan_percent: pool_scan_percent,
          checked_at: pool_check.to_i,
        },
      }

      @exchange.publish(
        status.to_json,
        content_type: 'application/json',
        routing_key: $CFG.get(:vpsadmin, :routing_key),
      )
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
      return @cgroup_version if @cgroup_version

      path = '/run/osctl/cgroup.version'

      begin
        @cgroup_version = File.read(path).strip.to_i
      rescue SystemCallError => e
        unless $CFG.minimal?
          log(:info, "Unable to read cgroup version from #{path}: #{e.message} (#{e.class})")
        end

        @cgroup_version = 0
      end

      @cgroup_version
    end
  end
end
