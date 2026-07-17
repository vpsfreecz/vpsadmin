module VpsAdmin::API::NodeSystemStateData
  HOST_ROLES = %i[node storage].freeze
  CGROUP_ORDER = 'node_system_states.first_observed_at, node_system_states.id'.freeze

  def system_state_query(input, base_scope: ::NodeSystemState.all)
    scope = base_scope.joins(:node)
                      .includes(:node)
                      .where(nodes: { role: HOST_ROLES })
    scope = scope.where(node: input[:node]) if input[:node]
    scope = scope.where(current: input[:current]) if input.has_key?(:current)
    scope = scope.where('node_system_states.last_observed_at >= ?', input[:from]) if input[:from]
    scope = scope.where('node_system_states.first_observed_at <= ?', input[:to]) if input[:to]

    if current_user.role == :admin
      scope = scope.where(nodes: { active: input[:node_active] }) if input.has_key?(:node_active)
    else
      scope = scope.where(nodes: { active: true })
    end

    scope
  end

  def find_system_state(id)
    system_state_query({}).find(id)
  end

  def cgroup_state_query(input)
    system_state_query(input, base_scope: coalesced_cgroup_states)
  end

  def find_cgroup_state(id)
    cgroup_state_query({}).find(id)
  end

  def ordered_system_states(query = system_state_query(input), &find_cursor)
    find_cursor ||= method(:find_system_state)
    paginated = ar_with_pagination(query, check: true) do |scope, from_id|
      cursor = find_cursor.call(from_id)
      scope.where(
        'node_system_states.first_observed_at < :observed_at OR ' \
        '(node_system_states.first_observed_at = :observed_at ' \
        'AND node_system_states.id < :id)',
        observed_at: cursor.first_observed_at,
        id: cursor.id
      )
    end

    paginated.order(first_observed_at: :desc, id: :desc)
  end

  def ordered_cgroup_states
    ordered_system_states(cgroup_state_query(input)) { |id| find_cgroup_state(id) }
  end

  protected

  def coalesced_cgroup_states
    boundaries = ::NodeSystemState.unscoped.select(
      'node_system_states.*',
      <<~SQL.squish
        CASE
          WHEN ROW_NUMBER() OVER (
            PARTITION BY node_system_states.node_id ORDER BY #{CGROUP_ORDER}
          ) = 1 THEN 1
          WHEN node_system_states.cgroup_version <=> LAG(node_system_states.cgroup_version) OVER (
            PARTITION BY node_system_states.node_id ORDER BY #{CGROUP_ORDER}
          ) THEN 0
          ELSE 1
        END AS cgroup_boundary
      SQL
    )
    runs = ::NodeSystemState.unscoped
                            .from("(#{boundaries.to_sql}) node_system_states")
                            .select(
                              'node_system_states.*',
                              <<~SQL.squish
                                SUM(node_system_states.cgroup_boundary) OVER (
                                  PARTITION BY node_system_states.node_id
                                  ORDER BY #{CGROUP_ORDER}
                                  ROWS UNBOUNDED PRECEDING
                                ) AS cgroup_run
                              SQL
                            )
    coalesced = ::NodeSystemState.unscoped
                                 .from("(#{runs.to_sql}) node_system_state_runs")
                                 .select(
                                   'MIN(node_system_state_runs.id) AS id',
                                   'node_system_state_runs.node_id',
                                   'NULL AS cpus',
                                   'NULL AS total_memory',
                                   'NULL AS total_swap',
                                   'node_system_state_runs.cgroup_version',
                                   'MIN(node_system_state_runs.first_observed_at) AS first_observed_at',
                                   'MAX(node_system_state_runs.last_observed_at) AS last_observed_at',
                                   'MAX(node_system_state_runs.current) AS current',
                                   'NULL AS created_at',
                                   'NULL AS updated_at'
                                 )
                                 .group(
                                   'node_system_state_runs.node_id',
                                   'node_system_state_runs.cgroup_run',
                                   'node_system_state_runs.cgroup_version'
                                 )

    ::NodeSystemState.unscoped.from("(#{coalesced.to_sql}) node_system_states")
  end
end
