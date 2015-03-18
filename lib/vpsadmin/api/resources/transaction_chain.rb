class VpsAdmin::API::Resources::TransactionChain < HaveAPI::Resource
  version 1
  model ::TransactionChain
  desc 'Access transaction chains'

  params(:all) do
    id :id, label: 'Chain ID'
    string :name, label: 'Name', desc: 'For internal use only'
    string :label, label: 'Label', desc: 'Human-friendly name'
    string :state, label: 'State', choices: ::TransactionChain.states.keys
    integer :size, label: 'Size', desc: 'Number of transactions in the chain'
    integer :progress, label: 'Progress', desc: 'How many transactions are finished'
    resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
    datetime :created_at, label: 'Creation date'
    custom :concerns, db_name: :format_concerns
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List transaction chains'

    input do
      string :name, label: 'Name', desc: 'For internal use only'
      string :state, label: 'State', choices: ::TransactionChain.states.keys
      resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
      string :class_name, label: 'Class name', desc: 'Search by concerned class name'
      integer :row_id, label: 'Row id', desc: 'Search by concerned row id'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      output blacklist: %i(user)
      allow
    end

    def query
      q = ::TransactionChain.where(with_restricted)

      q = q.where(name: input[:name]) if input[:name]
      q = q.where(state: ::TransactionChain.states[input[:state]]) if input[:state]
      q = q.where(user: input[:user]) if input[:user]
      q = q.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: {class_name: input[:class_name]}
      ) if input[:class_name]
      q = q.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: {row_id: input[:row_id]}
      ) if input[:row_id]

      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query)
          .includes(:transaction_chain_concerns)
          .limit(input[:limit])
          .offset(input[:offset])
          .order('transaction_chains.created_at DESC')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show transaction chain'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      output blacklist: %i(user)
      allow
    end

    def prepare
      @chain = ::TransactionChain.find_by!(with_restricted(id: params[:transaction_chain_id]))
    end

    def exec
      @chain
    end
  end

  class Transaction < HaveAPI::Resource
    version 1
    desc 'Access transactions linked in a chain'
    route ':transaction_chain_id/transactions'
    model ::Transaction

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Node, label: 'Node', value_label: :name
      resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
      integer :type, db_name: :t_type
      string :name
      resource Transaction, name: :depends_on, label: 'Depends on'
      bool :urgent, db_name: :t_urgent
      integer :priority, db_name: :t_priority
      integer :success, db_name: :t_success
      string :done, db_name: :t_done, choices: ::Transaction.t_dones.keys
      string :input, db_name: :t_param
      string :output, db_name: :t_output
      datetime :created_at
      datetime :started_at
      datetime :finished_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List transactions'

      input do
        resource VpsAdmin::API::Resources::Node, label: 'Node', value_label: :name
        integer :type, db_name: :t_type
        integer :success, db_name: :t_success
        string :done, db_name: :t_done, choices: ::Transaction.t_dones.keys
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        output blacklist: %i(user type urgent priority input output)
        allow
      end

      def query
        q = ::Transaction.where(with_restricted(transaction_chain_id: params[:transaction_chain_id]))

        q = q.where(node: input[:node]) if input[:node]
        q = q.where(t_type: input[:type]) if input[:type]
        q = q.where(t_success: input[:success]) if input[:success]
        q = q.where(t_done: ::Transaction.t_dones[input[:done]]) if input[:done]

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset]).order('t_id DESC')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show transaction'
      resolve ->(t){ [t.transaction_chain_id, t.id] }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        output blacklist: %i(user type urgent priority input output)
        allow
      end

      def prepare
        @trans = ::Transaction.find_by!(
            with_restricted(
                transaction_chain_id: params[:transaction_chain_id],
                t_id: params[:transaction_id]
            )
        )
      end

      def exec
        @trans
      end
    end
  end
end
