class VpsAdmin::API::Resources::Environment < HaveAPI::Resource
  model ::Environment
  desc 'Manage environments'

  params(:id) do
    integer :id, label: 'ID', desc: 'Environment ID'
  end

  params(:common) do
    string :label, desc: 'Environment label'
    string :description, desc: 'Environment description'
    string :domain, desc: 'Environment FQDN, should be subject\'s root domain'
    bool :can_create_vps, label: 'Can create a VPS', default: false
    bool :can_destroy_vps, label: 'Can destroy a VPS', default: false
    integer :vps_lifetime, label: 'Default VPS lifetime',
                           desc: 'in seconds, 0 is unlimited', default: 0
    integer :max_vps_count, label: 'Maximum number of VPS per user',
                            desc: '0 is unlimited', default: 1
    bool :user_ip_ownership, label: 'User owns IP addresses', default: true
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List environments'

    input do
      bool :has_hypervisor, label: 'Has hypervisor',
                            desc: 'List only environments having at least one hypervisor'
      bool :has_storage, label: 'Has storage',
                         desc: 'List only environments having at least one storage'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i[id label description]
      allow
    end

    example do
      request({})
      response([
                 {
                   id: 1,
                   label: 'Production',
                   domain: 'vpsfree.cz'
                 }
               ])
    end

    def query
      q = ::Environment.all

      has = []
      not_has = []

      if input[:has_hypervisor]
        has << 'node'

      elsif input[:has_hypervisor] === false
        not_has << 'node'
      end

      if input[:has_storage]
        has << 'storage'

      elsif input[:has_storage] === false
        not_has << 'storage'
      end

      unless has.empty?
        q = q.joins(locations: :nodes).where(
          nodes: { role: has }
        ).group('environments.id')
      end

      unless not_has.empty?
        q = q.joins(locations: :nodes).where.not(
          nodes: { role: not_has }
        ).group('environments.id')
      end

      q
    end

    def count
      query.count
    end

    def exec
      query.limit(input[:limit]).offset(input[:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new environment'

    input do
      use :common
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      authorize { |u| u.role == :admin }
      request({
                label: 'Devel',
                domain: 'vpsfree.cz'
              })
      response({
                 id: 2
               })
    end

    def exec
      env = ::Environment.new(input)

      if env.save
        ok(env)
      else
        error('save failed', to_param_names(env.errors.to_hash, :input))
      end
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show environment'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i[id label description]
      allow
    end

    example do
      path_params(1)
      request({})
      response({
                 id: 1,
                 label: 'Production',
                 domain: 'vpsfree.cz'
               })
    end

    def exec
      ::Environment.find(params[:environment_id])
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update environment'

    input do
      use :common
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    example do
      authorize { |u| u.role == :admin }
      path_params(1)
      request({
                label: 'My new name',
                domain: 'new.domain'
              })
      response({})
    end

    def exec
      VpsAdmin::API::Operations::Environment::Update.run(
        ::Environment.find(params[:environment_id]),
        input
      )
    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record.errors.to_hash)
    end
  end

  # class Delete < HaveAPI::Actions::Default::Delete
  #   desc 'Delete environment'
  #
  #   authorize do |u|
  #     allow if u.role == :admin
  #   end
  #
  #   example do
  #     request({})
  #     response({})
  #   end
  #
  #   def exec
  #     ::Environment.find(params[:environment_id]).destroy
  #   end
  # end

  include VpsAdmin::API::Maintainable::Action

  class DatasetPlan < HaveAPI::Resource
    route '{environment_id}/dataset_plans'
    desc 'Manage environment dataset plans'
    model ::EnvironmentDatasetPlan

    params(:id) do
      integer :id, label: 'ID'
    end

    params(:common) do
      string :label
      resource VpsAdmin::API::Resources::DatasetPlan, value_label: :label
      bool :user_add, label: 'User add',
                      desc: 'If true, the user can add this plan to a dataset'
      bool :user_remove, label: 'User remove',
                         desc: 'If true, the user can remove this plan from a dataset'
    end

    params(:all) do
      use :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List dataset plans'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_add: true
        allow
      end

      def query
        ::EnvironmentDatasetPlan.where(with_restricted(
                                         environment_id: params[:environment_id]
                                       ))
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show dataset plan'
      resolve ->(p) { [p.environment_id, p.id] }

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        ::EnvironmentDatasetPlan.find_by!(
          environment_id: params[:environment_id],
          id: params[:dataset_plan_id]
        )
      end
    end
  end
end
