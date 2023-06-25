module VpsAdmin::API::Resources
  class DatasetExpansion < HaveAPI::Resource
    model ::DatasetExpansion
    desc 'Browse dataset expansions'

    params(:id) do
      integer :id, label: 'ID'
    end

    params(:common) do
      resource Dataset, value_label: :name
      string :state, choices: ::DatasetExpansion.states.keys.map(&:to_s)
      integer :original_refquota, label: 'Original reference quota'
      integer :added_space, label: 'Added space'
      bool :enable_notifications, label: 'Enable notifications',
        desc: 'Send emails about the expansion'
      bool :stop_vps, label: 'Stop VPS',
        desc: 'Stop the VPS after deadline passes or too many expansions'
      datetime :deadline
      datetime :created_at
    end

    params(:all) do
      use :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List dataset expansions'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict datasets: {user_id: u.id}
        allow
      end

      def query
        ::DatasetExpansion.joins(:dataset).where(with_restricted)
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show dataset expansion'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict datasets: {user_id: u.id}
        allow
      end

      def prepare
        @exp = ::DatasetExpansion.joins(:dataset).find_by!(with_restricted(
          id: params[:dataset_expansion_id],
        ))
      end

      def exec
        @exp
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create dataset expansion'
      blocking true

      input do
        use :common, include: %i(dataset added_space enable_notifications stop_vps deadline)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        if input[:dataset].dataset_expansion_id
          error('this dataset is already expanded')
        end

        exp = ::DatasetExpansion.new(
          dataset: input[:dataset],
          added_space: input[:added_space],
          enable_notifications: input[:enable_notifications],
          deadline: input[:deadline],
        )

        @chain, ret = TransactionChains::Dataset::Expand.fire(exp)
        ret
      end

      def state_id
        @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update dataset expansion'

      input do
        use :common, include: %i(enable_notifications stop_vps deadline)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        exp = ::DatasetExpansion.joins(:dataset).find_by!(with_restricted(
          id: params[:dataset_expansion_id],
        ))
        exp.update!(input)
      end
    end

    class History < HaveAPI::Resource
      route '{dataset_expansion_id}/history'
      model ::DatasetExpansionHistory
      desc 'Browse dataset expansion history'

      params(:all) do
        id :id
        integer :added_space, label: 'Added space'
        integer :original_refquota, label: 'Original refquota'
        integer :new_refquota, label: 'New refquota'
        datetime :created_at, label: 'Created at'
        resource User, name: :admin, value_label: :login
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List dataset expansion history'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def query
          ::DatasetExpansionHistory.joins(dataset_expansion: :dataset).where(
            with_restricted(dataset_expansions: {id: params[:dataset_expansion_id]})
          )
        end

        def count
          query.count
        end

        def exec
          query.order('created_at').limit(input[:limit]).offset(input[:offset])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show dataset expansion history'
        resolve ->(hist){ [hist.dataset_expansion_id, hist.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict datasets: {user_id: u.id}
          allow
        end

        def prepare
          @hist = ::DatasetExpansionHistory.joins(dataset_expansion: :dataset).find_by!(
            with_restricted(
              dataset_expansions: {id: params[:dataset_expansion_id]},
              id: params[:history_id],
            )
          )
        end

        def exec
          @hist
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Add extra space to the dataset'
        blocking true

        input do
          use :all, include: %i(added_space)
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          exp = ::DatasetExpansion.find(params[:dataset_expansion_id])

          if exp.state != 'active'
            error('this expansion is already resolved')
          end

          hist = exp.dataset_expansion_histories.new(
            added_space: input[:added_space],
            admin: current_user,
          )

          @chain, ret = TransactionChains::Dataset::ExpandAgain.fire(hist)
          ret
        end

        def state_id
          @chain.id
        end
      end
    end
  end
end
