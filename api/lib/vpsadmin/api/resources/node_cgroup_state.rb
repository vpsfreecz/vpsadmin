module VpsAdmin::API::Resources
  class NodeCgroupState < HaveAPI::Resource
    desc 'Observed Node cgroup-version history'
    model ::NodeSystemState

    params(:filters) do
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      bool :node_active
      bool :current
      datetime :from
      datetime :to
    end

    params(:all) do
      id :id, label: 'ID'
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      string :cgroup_version, label: 'Cgroup version', nullable: true,
                              choices: ::NodeSystemState.cgroup_versions.keys
      datetime :first_observed_at, label: 'First observed at'
      datetime :last_observed_at, label: 'Last observed at'
      bool :current
    end

    class Index < HaveAPI::Actions::Default::Index
      include VpsAdmin::API::NodeSystemStateData

      input do
        use :filters
        patch :limit, default: 1000, fill: true
      end

      output(:object_list) { use :all }

      authorize do |user|
        allow if user.role == :admin
        input blacklist: %i[node_active]
        allow if user
      end

      def query = cgroup_state_query(input)
      def count = query.count
      def exec = ordered_cgroup_states
    end

    class Show < HaveAPI::Actions::Default::Show
      include VpsAdmin::API::NodeSystemStateData

      output { use :all }
      authorize { |user| allow if user }

      def prepare
        @state = find_cgroup_state(path_params['node_cgroup_state_id'])
      end

      def exec = @state
    end
  end
end
