require 'fileutils'
require 'libosctl'
require 'prometheus/client'
require 'prometheus/client/formats/text'

module NodeCtld
  class Exporter
    include OsCtl::Lib::Utils::File

    Metrics = Struct.new(
      :state_initialized,
      :state_run,
      :state_paused,
      :start_time_seconds,
      :open_console,
      :subprocess,
      :queue_started,
      :queue_used,
      :queue_reserved,
      :queue_slots,
      :queue_urgent,
      :queue_total,
      :command_seconds,
      :vps_autostart_check_success,
      :vps_autostart_check_last_success_timestamp_seconds,
      :vps_autostart_expected,
      :vps_autostart_unsatisfied,
      :vps_autostart_unsatisfied_reason,
      :vps_autostart_unsatisfied_count,
      :vps_autostart_mismatch
    )

    def initialize(daemon)
      @daemon = daemon
      @queue = OsCtl::Lib::Queue.new
    end

    def start
      @thread = Thread.new { run_exporter }
    end

    def stop
      @queue << :stop
    end

    protected

    def run_exporter
      export_metrics

      loop do
        v = @queue.pop(timeout: $CFG.get(:exporter, :interval))
        return if v == :stop

        export_metrics
      end
    end

    def export_metrics
      registry = Prometheus::Client::Registry.new
      metrics = setup_metrics(registry)
      collect_metrics(metrics)

      d = $CFG.get(:exporter, :metrics_dir)
      FileUtils.mkdir_p(d)
      regenerate_file(File.join(d, 'nodectld.prom'), 0o644) do |new|
        new.write(Prometheus::Client::Formats::Text.marshal(registry))
      end
    end

    def setup_metrics(registry)
      Metrics.new(
        state_initialized: registry.gauge(
          :nodectld_state_initialized,
          docstring: 'nodectld initialized flag'
        ),
        state_run: registry.gauge(
          :nodectld_state_run,
          docstring: 'nodectld run flag'
        ),
        state_paused: registry.gauge(
          :nodectld_state_paused,
          docstring: 'nodectld paused flag'
        ),
        start_time_seconds: registry.gauge(
          :nodectld_start_time_seconds,
          docstring: 'Number of seconds since nodectld was started'
        ),
        open_console: registry.gauge(
          :nodectld_open_console,
          docstring: 'Currently opened VPS consoles',
          labels: %i[vps_id]
        ),
        subprocess: registry.gauge(
          :nodectld_chain_subprocess,
          docstring: 'Background processes',
          labels: %i[chain_id subprocess_pid]
        ),
        queue_started: registry.gauge(
          :nodectld_queue_started,
          docstring: 'Set if the queue is open',
          labels: %i[queue]
        ),
        queue_used: registry.gauge(
          :nodectld_queue_used_slots,
          docstring: 'Number of used queue slots',
          labels: %i[queue]
        ),
        queue_reserved: registry.gauge(
          :nodectld_queue_reserved_slots,
          docstring: 'Number of reserved slots in a queue',
          labels: %i[queue]
        ),
        queue_slots: registry.gauge(
          :nodectld_queue_max_slots,
          docstring: 'Maximum number of threads in a queue',
          labels: %i[queue]
        ),
        queue_urgent: registry.gauge(
          :nodectld_queue_urgent_slots,
          docstring: 'Number of urgent threads in a queue',
          labels: %i[queue]
        ),
        queue_total: registry.gauge(
          :nodectld_queue_total_slots,
          docstring: 'Total number of threads in a queue, including urgent',
          labels: %i[queue]
        ),
        command_seconds: registry.gauge(
          :nodectld_command_seconds,
          docstring: 'Number of seconds an executed command (transaction) is running for',
          labels: %i[chain_id transaction_id queue type handler]
        ),
        vps_autostart_check_success: registry.gauge(
          :nodectld_vps_autostart_check_success,
          docstring: 'Whether the latest VPS auto-start status check succeeded'
        ),
        vps_autostart_check_last_success_timestamp_seconds: registry.gauge(
          :nodectld_vps_autostart_check_last_success_timestamp_seconds,
          docstring: 'Unix timestamp of the latest successful VPS auto-start status check'
        ),
        vps_autostart_expected: registry.gauge(
          :nodectld_vps_autostart_expected,
          docstring: 'Number of VPSes expected to be running after auto-start',
          labels: %i[pool]
        ),
        vps_autostart_unsatisfied: registry.gauge(
          :nodectld_vps_autostart_unsatisfied,
          docstring: 'Whether an auto-start VPS is not running',
          labels: %i[pool vps_id]
        ),
        vps_autostart_unsatisfied_reason: registry.gauge(
          :nodectld_vps_autostart_unsatisfied_reason,
          docstring: 'Reason an auto-start VPS is not running',
          labels: %i[pool vps_id reason]
        ),
        vps_autostart_unsatisfied_count: registry.gauge(
          :nodectld_vps_autostart_unsatisfied_count,
          docstring: 'Number of auto-start VPSes that are not running',
          labels: %i[pool reason]
        ),
        vps_autostart_mismatch: registry.gauge(
          :nodectld_vps_autostart_mismatch,
          docstring: 'Difference between vpsAdmin and osctld auto-start settings',
          labels: %i[pool vps_id vpsadmin osctld]
        )
      )
    end

    def collect_metrics(metrics)
      metrics.state_initialized.set(@daemon.initialized? ? 1 : 0)
      metrics.state_run.set(@daemon.run? ? 1 : 0)
      metrics.state_paused.set(@daemon.paused? ? 1 : 0)
      metrics.start_time_seconds.set((Time.now - @daemon.start_time).to_i)

      @daemon.console.stats.each_key do |vps_id|
        metrics.open_console.set(1, labels: { vps_id: })
      end

      @daemon.chain_blockers do |blockers|
        next unless blockers

        blockers.each do |chain_id, pids|
          pids.each do |pid|
            metrics.subprocess.set(1, labels: { chain_id:, subprocess_pid: pid })
          end
        end
      end

      @daemon.queues.each do |name, queue|
        metrics.queue_started.set(queue.started? ? 1 : 0, labels: { queue: name })
        metrics.queue_used.set(queue.used, labels: { queue: name })
        metrics.queue_reserved.set(queue.reservations.size, labels: { queue: name })
        metrics.queue_slots.set(queue.size, labels: { queue: name })
        metrics.queue_urgent.set(queue.urgent_size, labels: { queue: name })
        metrics.queue_total.set(queue.size + queue.urgent_size, labels: { queue: name })

        queue.each_value do |w|
          cmd = w.cmd
          start_time = cmd.time_start

          metrics.command_seconds.set(
            start_time ? (Time.now - start_time).to_i : 0,
            labels: {
              chain_id: cmd.chain_id,
              transaction_id: cmd.id,
              queue: name,
              type: cmd.type,
              handler: cmd.handler.split('::')[-2..].join('::')
            }
          )
        end
      end

      collect_vps_autostart_metrics(metrics)
    end

    def collect_vps_autostart_metrics(metrics)
      snapshot = @daemon.vps_status.vps_autostart_status.snapshot

      metrics.vps_autostart_check_success.set(snapshot.success ? 1 : 0)
      metrics.vps_autostart_check_last_success_timestamp_seconds.set(
        snapshot.last_success_at
      )

      snapshot.expected.each do |pool, count|
        metrics.vps_autostart_expected.set(count, labels: { pool: })
      end

      snapshot.unsatisfied.each do |vps|
        labels = { pool: vps.pool, vps_id: vps.vps_id }
        metrics.vps_autostart_unsatisfied.set(1, labels:)
        metrics.vps_autostart_unsatisfied_reason.set(
          1,
          labels: labels.merge(reason: vps.reason)
        )
      end

      snapshot.unsatisfied_counts.each do |(pool, reason), count|
        metrics.vps_autostart_unsatisfied_count.set(
          count,
          labels: { pool:, reason: }
        )
      end

      snapshot.mismatches.each do |vps|
        metrics.vps_autostart_mismatch.set(
          1,
          labels: {
            pool: vps.pool,
            vps_id: vps.vps_id,
            vpsadmin: vps.vpsadmin,
            osctld: vps.osctld
          }
        )
      end
    end
  end
end
