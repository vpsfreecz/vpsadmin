require 'time'

module VpsAdmin::API::Tasks
  class NodeHistoryBackfill < Base
    COMPONENTS = {
      kernel: {
        operation: 'VpsAdmin::API::Operations::Node::ReconstructKernelEvents'
      },
      system: {
        operation: 'VpsAdmin::API::Operations::Node::ReconstructSystemStates'
      }
    }.freeze

    def initialize(io: $stdout, env: ENV, progress_reporter: ProgressReporter)
      super()
      @io = io
      @env = env
      @progress_reporter = progress_reporter
    end

    def reconstruct(components: COMPONENTS.keys)
      components = Array(components).map(&:to_sym)
      validate_components(components)
      batch_size = parse_batch_size
      force = parse_force
      selected = selected_nodes
      all_nodes = eligible_nodes

      print_summary('Before', all_nodes)
      pending = selected.select do |node|
        force || components.any? { |component| !component_complete?(node, component) }
      end

      if pending.empty?
        @io.puts "No pending #{component_label(components)} history backfills"
        selected.each { |node| print_run_status(node) }
        print_summary('After', all_nodes)
        return 0
      end

      created = 0
      begin
        pending.each do |node|
          components.each do |component|
            next if !force && component_complete?(node, component)

            created += reconstruct_component(node, component, batch_size:, force:)
          end
        ensure
          print_run_status(node)
        end
      ensure
        print_summary('After', all_nodes)
      end
      created
    end

    def status
      nodes = selected_nodes
      @io.puts %w[
        ID
        NAME
        ROLE
        ACTIVE
        OVERALL
        KERNEL
        KERNEL_COMPLETED_AT
        KERNEL_STATUS_IDS
        KERNEL_OBSERVATIONS
        SYSTEM
        SYSTEM_COMPLETED_AT
        SYSTEM_STATUS_IDS
        SYSTEM_OBSERVATIONS
      ].join("\t")
      nodes.each { |node| print_status(node) }
      print_summary('Status', nodes)
      nil
    end

    protected

    def reconstruct_component(node, component, batch_size:, force:)
      label = "node=#{node.id}/#{node.domain_name} task=#{component}"
      @io.puts "#{label}: preparing"
      reporter = @progress_reporter.new(label:, io: @io)
      COMPONENTS.fetch(component).fetch(:operation).constantize.run(
        node,
        batch_size:,
        force:,
        progress: reporter
      )
    end

    def eligible_nodes
      ::Node.where(role: %i[node storage])
            .includes(:location, :node_kernel_history_state, :node_system_history_state)
            .order(:id)
            .to_a
    end

    def selected_nodes
      value = @env['NODE_ID'].to_s.strip
      return eligible_nodes if value.empty?

      id = parse_positive_integer(value, 'NODE_ID')
      node = ::Node.includes(:location, :node_kernel_history_state, :node_system_history_state)
                   .find_by(id:)
      raise ArgumentError, "Node #{id} does not exist" unless node
      unless node.node? || node.storage?
        raise ArgumentError, "Node #{id} has service-only role #{node.role}"
      end

      [node]
    end

    def parse_batch_size
      value = @env['BATCH_SIZE'].to_s.strip
      if value.empty?
        return VpsAdmin::API::Operations::Node::HistoryBackfill::DEFAULT_BATCH_SIZE
      end

      parse_positive_integer(value, 'BATCH_SIZE')
    end

    def parse_force
      value = @env['FORCE'].to_s.strip
      return false if value.empty? || value == '0'
      return true if value == '1'

      raise ArgumentError, 'FORCE must be 1 when set'
    end

    def parse_positive_integer(value, name)
      parsed = Integer(value, 10)
      raise ArgumentError unless parsed > 0

      parsed
    rescue ArgumentError
      raise ArgumentError, "#{name} must be a positive integer"
    end

    def validate_components(components)
      invalid = components - COMPONENTS.keys
      raise ArgumentError, "Unknown history component #{invalid.first}" if invalid.any?
    end

    def component_complete?(node, component)
      association = component == :kernel ? :node_kernel_history_state : :node_system_history_state
      checkpoint_for(node, association).present?
    end

    def component_label(components)
      components.length == 1 ? components.first : 'combined'
    end

    def print_status(node)
      kernel = checkpoint_for(node, :node_kernel_history_state)
      system = checkpoint_for(node, :node_system_history_state)
      @io.puts [
        node.id,
        node.domain_name,
        node.role,
        node.active? ? 'yes' : 'no',
        overall_state(kernel, system),
        component_state(kernel),
        format_time(kernel&.completed_at),
        format_status_ids(kernel),
        format_observations(kernel),
        component_state(system),
        format_time(system&.completed_at),
        format_status_ids(system),
        format_observations(system)
      ].join("\t")
    end

    def print_run_status(node)
      kernel = checkpoint_for(node, :node_kernel_history_state)
      system = checkpoint_for(node, :node_system_history_state)
      @io.puts [
        "node=#{node.id}/#{node.domain_name}",
        "overall=#{overall_state(kernel, system)}",
        "kernel=#{component_state(kernel)}",
        "kernel_completed_at=#{format_time(kernel&.completed_at)}",
        "kernel_status_ids=#{format_status_ids(kernel)}",
        "kernel_observations=#{format_observations(kernel)}",
        "system=#{component_state(system)}",
        "system_completed_at=#{format_time(system&.completed_at)}",
        "system_status_ids=#{format_status_ids(system)}",
        "system_observations=#{format_observations(system)}"
      ].join(' ')
    end

    def print_summary(prefix, nodes)
      counts = Hash.new(0)
      nodes.each do |node|
        kernel = checkpoint_for(node, :node_kernel_history_state)
        system = checkpoint_for(node, :node_system_history_state)
        counts[overall_state(kernel, system)] += 1
      end
      @io.puts format(
        '%<prefix>s history backfill totals: pending=%<pending>d ' \
        'partial=%<partial>d complete=%<complete>d total=%<total>d',
        prefix:,
        pending: counts['pending'],
        partial: counts['partial'],
        complete: counts['complete'],
        total: nodes.length
      )
    end

    def overall_state(kernel, system)
      completed = [kernel, system].count(&:present?)
      return 'complete' if completed == 2
      return 'partial' if completed == 1

      'pending'
    end

    def checkpoint_for(node, name)
      association = node.association(name)
      association.reload
      association.target
    end

    def component_state(state)
      state ? 'complete' : 'pending'
    end

    def format_status_ids(state)
      return '-' unless state

      "#{state.from_status_id || '-'}..#{state.through_status_id || '-'}"
    end

    def format_observations(state)
      return '-' unless state

      "#{format_time(state.started_at)}..#{format_time(state.observed_through)}"
    end

    def format_time(value)
      value ? value.iso8601(6) : '-'
    end
  end
end
