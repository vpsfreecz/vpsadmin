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
      keyword_init: true
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

      @daemon.queues do |queues|
        queues.each do |name, queue|
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
      end
    end
  end
end
