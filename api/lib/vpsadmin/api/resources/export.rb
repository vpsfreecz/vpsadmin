class VpsAdmin::API::Resources::Export < HaveAPI::Resource
  model ::Export
  desc 'Manage NFS exports'

  params(:all) do
    id :id, label: 'Export ID'
    resource VpsAdmin::API::Resources::Dataset, value_label: :name
    resource VpsAdmin::API::Resources::Dataset::Snapshot, value_label: :created_at
    resource VpsAdmin::API::Resources::User, value_label: :login
    resource VpsAdmin::API::Resources::IpAddress, value_label: :addr
    resource VpsAdmin::API::Resources::HostIpAddress, value_label: :addr
    string :path
    bool :all_vps, label: 'All VPS',
      desc: "Let all user's VPS to mount this export. Changes to the user's "+
            "IP addresses will automatically add or remove allowed hosts on "+
            "the export."
    bool :rw, label: 'Read-write',
      desc: 'Allow the export to be mounted as read-write.'
    bool :sync, label: 'Sync',
      desc: "Determines whether the server replies to requests only after the "+
            "changes have been committed to stable storage."
    bool :subtree_check, label: 'Subtree check', desc: 'See man exports(5).'
    bool :root_squash, label: 'Root squash',
      desc: "Map requests from uid/gid 0 to the anonymous uid/gid. Note that "+
            "this does not apply to any other uids or gids that might be "+
            "equally sensitive."
    bool :enabled
    datetime :expiration_date, label: 'Expiration date'
    datetime :created_at
    datetime :updated_at
  end

  params(:editable) do
    use :all, include: %i(all_vps rw sync subtree_check root_squash enabled)
  end

  params(:filters) do
    use :all, include: %i(user)
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List exports'

    input do
      use :filters
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      input whitelist: %i(limit offset)
      allow
    end

    def query
      q = self.class.model.where(with_restricted)
      q = q.where(user: input[:user]) if input[:user]
      q
    end

    def count
      query.count
    end

    def exec
      query.limit(input[:limit]).offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def prepare
      @export = self.class.model.find_by!(with_restricted(
        id: params[:export_id],
      ))
    end

    def exec
      @export
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create a new export'
    blocking true

    input do
      use :all, include: %i(dataset snapshot)
      use :editable

      patch :all_vps, default: true, fill: true
      patch :rw, default: true, fill: true
      patch :subtree_check, default: false, fill: true
      patch :root_squash, default: false, fill: true
      patch :sync, default: true, fill: true
      patch :enabled, default: true, fill: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def exec
      if (input[:dataset] && input[:snapshot]) \
         || (!input[:dataset] && !input[:snapshot])
        error('provide either dataset or snapshot')
      end

      ds =
        if input[:dataset]
          input[:dataset]
        else
          input[:snapshot].dataset
        end

      if !current_user.role == :admin && ds.user_id != current_user.id
        error('access denied')
      end

      @chain, export = VpsAdmin::API::Operations::Export::Create.run(
        ds,
        input.clone
      )
      export

    rescue VpsAdmin::API::Exceptions::DatasetAlreadyExported => e
      error(e.message)
    end

    def state_id
      @chain.id
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Edit export'
    blocking true

    input do
      use :editable
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def exec
      export = self.class.model.find_by!(with_restricted(
        id: params[:export_id],
      ))

      @chain, export = VpsAdmin::API::Operations::Export::Update.run(
        export,
        input.clone
      )

      export
    end

    def state_id
      @chain.id
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete export'
    blocking true

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def exec
      export = self.class.model.find_by!(with_restricted(
        id: params[:export_id],
      ))

      @chain, export = VpsAdmin::API::Operations::Export::Destroy.run(export)
      ok
    end

    def state_id
      @chain.id
    end
  end

  class Host < HaveAPI::Resource
    desc 'Manage allowed hosts'
    route '{export_id}/hosts'
    model ::ExportHost

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::IpAddress, value_label: :addr
      bool :rw, label: 'Read-write',
        desc: 'Allow the export to be mounted as read-write.'
      bool :sync, label: 'Sync',
        desc: "Determines whether the server replies to requests only after the "+
              "changes have been committed to stable storage."
      bool :subtree_check, label: 'Subtree check', desc: 'See man exports(5).'
      bool :root_squash, label: 'Root squash',
        desc: "Map requests from uid/gid 0 to the anonymous uid/gid. Note that "+
              "this does not apply to any other uids or gids that might be "+
              "equally sensitive."
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List hosts'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict exports: {user_id: u.id}
        allow
      end

      def query
        self.class.model.joins(:export).where(with_restricted(
          exports: {id: params[:export_id]},
        ))
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict exports: {user_id: u.id}
        allow
      end

      def prepare
        @host = self.class.model.joins(:export).find_by!(with_restricted(
          exports: {id: params[:export_id]},
          id: params[:host_id],
        ))
      end

      def exec
        @host
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add a new host'
      blocking true

      input do
        use :all, include: %i(ip_address rw sync subtree_check root_squash)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict exports: {user_id: u.id}
        allow
      end

      def exec
        export = ::Export.find_by!(with_restricted(
          id: params[:export_id],
        ))

        @chain, host = VpsAdmin::API::Operations::Export::AddHost.run(
          export,
          input,
        )

        host

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', to_param_names(e.record.errors.to_hash))
      end

      def state_id
        @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Edit host options'
      blocking true

      input do
        use :all, include: %i(rw sync subtree_check root_squash)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        host = self.class.model.joins(:export).find_by!(with_restricted(
          exports: {id: params[:export_id]},
          id: params[:host_id],
        ))

        @chain, host = VpsAdmin::API::Operations::Export::EditHost.run(
          host,
          input.clone
        )

        host
      end

      def state_id
        @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete host'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict exports: {user_id: u.id}
        allow
      end

      def exec
        host = self.class.model.joins(:export).find_by!(with_restricted(
          exports: {id: params[:export_id]},
          id: params[:host_id],
        ))

        @chain = VpsAdmin::API::Operations::Export::DelHost.run(
          host.export,
          host,
        )

        ok
      end

      def state_id
        @chain.id
      end
    end
  end
end
