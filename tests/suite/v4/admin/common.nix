{
  adminUserId,
  node1Id,
}:
let
  base = import ../storage/remote-common.nix {
    inherit adminUserId node1Id;
    node2Id = node1Id;
    manageCluster = false;
  };
in
base
+ ''
  require 'securerandom'

  def setup_admin_cluster(services, node)
    [services, node].each(&:start)
    services.wait_for_vpsadmin_api
    wait_for_running_nodectld(node)
    wait_for_node_ready(services, node1_id)
    services.unlock_transaction_signing_key(passphrase: 'test')
  end

  def json_true?(value)
    value == true || value.to_i == 1
  end

  def environment_defaults_row(services, env_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', id,
        'can_create_vps', can_create_vps,
        'can_destroy_vps', can_destroy_vps,
        'vps_lifetime', vps_lifetime,
        'max_vps_count', max_vps_count
      )
      FROM environments
      WHERE id = #{Integer(env_id)}
      LIMIT 1
    SQL
  end

  def environment_user_configs(services, env_id:, user_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'environment_id', environment_id,
        'user_id', user_id,
        'default', `default`,
        'can_create_vps', can_create_vps,
        'can_destroy_vps', can_destroy_vps,
        'vps_lifetime', vps_lifetime,
        'max_vps_count', max_vps_count
      )
      FROM environment_user_configs
      WHERE environment_id = #{Integer(env_id)}
        AND user_id = #{Integer(user_id)}
      ORDER BY id
    SQL
  end

  def create_shared_package_via_api_ruby(services, label:, values:)
    services.api_ruby_json(code: <<~RUBY)
      pkg = ClusterResourcePackage.create!(label: #{label.inspect})
      values = #{values.transform_keys(&:to_s).inspect}

      values.each do |name, value|
        ClusterResourcePackageItem.create!(
          cluster_resource_package: pkg,
          cluster_resource: ClusterResource.find_by!(name: name),
          value: value
        )
      end

      puts JSON.dump(id: pkg.id, label: pkg.label)
    RUBY
  end

  def create_personal_package_via_api_ruby(services, user_id:, environment_id:, values:)
    services.api_ruby_json(code: <<~RUBY)
      user = User.find(#{Integer(user_id)})
      env = Environment.find(#{Integer(environment_id)})
      admin = User.find(#{admin_user_id})
      values = #{values.transform_keys(&:to_s).inspect}

      pkg = ClusterResourcePackage.find_or_initialize_by(user: user, environment: env)
      pkg.label = 'Personal package'
      pkg.save! if pkg.changed? || pkg.new_record?

      ClusterResource.find_each do |resource|
        UserClusterResource.find_or_create_by!(
          user: user,
          environment: env,
          cluster_resource: resource
        ) { |ucr| ucr.value = 0 }
      end

      values.each do |name, value|
        resource = ClusterResource.find_by!(name: name)
        item = ClusterResourcePackageItem.find_or_initialize_by(
          cluster_resource_package: pkg,
          cluster_resource: resource
        )
        item.value = value
        item.save! if item.changed? || item.new_record?
      end

      UserClusterResourcePackage.find_or_create_by!(
        cluster_resource_package: pkg,
        user: user,
        environment: env
      ) do |link|
        link.added_by = admin
        link.comment = 'admin suite personal'
      end

      user.calculate_cluster_resources_in_env(env)

      puts JSON.dump(id: pkg.id, label: pkg.label)
    RUBY
  end

  def assign_package_via_api_ruby(services, package_id:, user_id:, environment_id:, from_personal: false)
    assign_package_result_via_api_ruby(
      services,
      package_id: package_id,
      user_id: user_id,
      environment_id: environment_id,
      from_personal: from_personal
    ).tap do |result|
      raise "package assignment failed: #{result.inspect}" unless result.fetch('ok')
    end
  end

  def assign_package_result_via_api_ruby(services, package_id:, user_id:, environment_id:, from_personal: false)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      begin
        pkg = ClusterResourcePackage.find(#{Integer(package_id)})
        user = User.find(#{Integer(user_id)})
        env = Environment.find(#{Integer(environment_id)})
        assignment = pkg.assign_to(
          env,
          user,
          comment: 'admin suite assignment',
          from_personal: #{from_personal ? 'true' : 'false'}
        )

        puts JSON.dump(ok: true, id: assignment.id)
      rescue => e
        puts JSON.dump(ok: false, error: e.class.name, message: e.message)
      end
    RUBY
  end

  def user_cluster_resource_values(services, user_id:, environment_id:)
    rows = services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT('name', cr.name, 'value', ucr.value)
      FROM user_cluster_resources ucr
      INNER JOIN cluster_resources cr ON cr.id = ucr.cluster_resource_id
      WHERE ucr.user_id = #{Integer(user_id)}
        AND ucr.environment_id = #{Integer(environment_id)}
      ORDER BY cr.name
    SQL

    rows.to_h { |row| [row.fetch('name'), row.fetch('value').to_i] }
  end

  def package_item_values(services, package_id:)
    rows = services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT('name', cr.name, 'value', item.value)
      FROM cluster_resource_package_items item
      INNER JOIN cluster_resources cr ON cr.id = item.cluster_resource_id
      WHERE item.cluster_resource_package_id = #{Integer(package_id)}
      ORDER BY cr.name
    SQL

    rows.to_h { |row| [row.fetch('name'), row.fetch('value').to_i] }
  end

  def register_group_snapshot_plan_via_api_ruby(services, dataset_in_pool_id:, plan_name:)
    services.api_ruby_json(code: <<~RUBY)
      plan_name = #{plan_name.to_s.inspect}.to_sym
      VpsAdmin::API::DatasetPlans::Registrator.plan(
        plan_name,
        label: 'Admin suite plan'
      ) do |target|
        group_snapshot target, '00', '03', '*', '*', '*'
      end

      dip = DatasetInPool.find(#{Integer(dataset_in_pool_id)})
      plan = VpsAdmin::API::DatasetPlans::Registrator.plans.fetch(plan_name)
      EnvironmentDatasetPlan.find_or_create_by!(
        environment: dip.pool.node.location.environment,
        dataset_plan: plan.dataset_plan
      ) do |env_plan|
        env_plan.user_add = true
        env_plan.user_remove = true
      end

      dip_plan = plan.register(dip)
      action = DatasetAction.find_by!(
        pool: dip.pool,
        dataset_plan: plan.dataset_plan,
        action: DatasetAction.actions[:group_snapshot]
      )
      task = RepeatableTask.find_for!(action)
      group = GroupSnapshot.find_by!(dataset_in_pool: dip, dataset_action: action)

      puts JSON.dump(
        dataset_in_pool_plan_id: dip_plan.id,
        dataset_action_id: action.id,
        repeatable_task_id: task.id,
        group_snapshot_id: group.id
      )
    RUBY
  end

  def unregister_group_snapshot_plan_via_api_ruby(services, dataset_in_pool_id:, plan_name:)
    services.api_ruby_json(code: <<~RUBY)
      plan_name = #{plan_name.to_s.inspect}.to_sym
      VpsAdmin::API::DatasetPlans::Registrator.plan(
        plan_name,
        label: 'Admin suite plan'
      ) do |target|
        group_snapshot target, '00', '03', '*', '*', '*'
      end

      dip = DatasetInPool.find(#{Integer(dataset_in_pool_id)})
      plan = VpsAdmin::API::DatasetPlans::Registrator.plans.fetch(plan_name)
      plan.unregister(dip)

      puts JSON.dump(ok: true)
    RUBY
  end

  def dataset_plan_state(services, dataset_in_pool_id:, plan_name: nil)
    services.api_ruby_json(code: <<~RUBY)
      dip = DatasetInPool.find(#{Integer(dataset_in_pool_id)})
      actions = DatasetAction.where(
        pool: dip.pool,
        action: DatasetAction.actions[:group_snapshot]
      )
      if #{plan_name.nil? ? 'false' : 'true'}
        actions = actions.joins(:dataset_plan).where(
          dataset_plans: { name: #{plan_name.to_s.inspect} }
        )
      end
      actions = actions.to_a
      tasks = actions.filter_map { |action| RepeatableTask.find_for(action) }

      puts JSON.dump(
        dataset_in_pool_plan_count: DatasetInPoolPlan.where(dataset_in_pool: dip).count,
        dataset_action_count: actions.count,
        repeatable_task_count: tasks.count,
        group_snapshot_count: GroupSnapshot.where(dataset_in_pool: dip).count
      )
    RUBY
  end

  def create_location_network_primary_fixture(services)
    services.api_ruby_json(code: <<~RUBY)
      env = Environment.first
      primary_location = Location.first
      secondary_location = Location.create!(
        label: 'admin-location-' + SecureRandom.hex(4),
        domain: 'admin-location-' + SecureRandom.hex(4) + '.test',
        environment: env,
        remote_console_server: "",
        has_ipv6: false
      )
      network = Network.create!(
        label: 'Admin primary switch',
        address: '198.51.200.0',
        prefix: 24,
        ip_version: 4,
        role: :public_access,
        managed: true,
        split_access: :no_access,
        split_prefix: 32,
        purpose: :any,
        primary_location: primary_location
      )
      first = VpsAdmin::API::Operations::LocationNetwork::Create.run({
        location: primary_location,
        network: network,
        primary: true
      })
      second = VpsAdmin::API::Operations::LocationNetwork::Create.run({
        location: secondary_location,
        network: network,
        primary: false
      })

      puts JSON.dump(
        network_id: network.id,
        first_location_id: primary_location.id,
        second_location_id: secondary_location.id,
        first_location_network_id: first.id,
        second_location_network_id: second.id
      )
    RUBY
  end

  def switch_location_network_primary(services, location_network_id:)
    services.api_ruby_json(code: <<~RUBY)
      loc_net = LocationNetwork.find(#{Integer(location_network_id)})
      VpsAdmin::API::Operations::LocationNetwork::Update.run(loc_net, { primary: true })
      puts JSON.dump(ok: true)
    RUBY
  end

  def delete_location_network_via_api_ruby(services, location_network_id:)
    services.api_ruby_json(code: <<~RUBY)
      loc_net = LocationNetwork.find(#{Integer(location_network_id)})
      VpsAdmin::API::Operations::LocationNetwork::Delete.run(loc_net)
      puts JSON.dump(ok: true)
    RUBY
  end

  def location_network_rows(services, network_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'location_id', location_id,
        'network_id', network_id,
        'primary', `primary`,
        'priority', priority,
        'autopick', autopick,
        'userpick', userpick
      )
      FROM location_networks
      WHERE network_id = #{Integer(network_id)}
      ORDER BY id
    SQL
  end

  def network_row(services, network_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', id,
        'primary_location_id', primary_location_id
      )
      FROM networks
      WHERE id = #{Integer(network_id)}
      LIMIT 1
    SQL
  end
''
