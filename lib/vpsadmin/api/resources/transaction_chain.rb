class VpsAdmin::API::Resources::TransactionChain < HaveAPI::Resource
  version 1
  model ::TransactionChain
  desc 'Access transaction chains'

  params(:all) do
    id :id, label: 'Chain ID'
    string :name, label: 'Name', desc: 'For internal use only'
    string :label, label: 'Label', desc: 'Human-friendly name'
    string :state, label: 'State', choices: ::TransactionChain.states.values
    integer :size, label: 'Size', desc: 'Number of transactions in the chain'
    integer :progress, label: 'Progress', desc: 'How many transactions are finished'
    resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
    datetime :created_at, label: 'Creation date'
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List transaction chains'

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
      ::TransactionChain.where(with_restricted)
    end

    def count
      query.count
    end

    def exec
      with_includes(query).limit(input[:limit]).offset(input[:offset]).order('created_at DESC')
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
    model ::Transaction

    params(:all) do
      resource VpsAdmin::API::Resources::Node, label: 'Node', value_label: :name
      resource VpsAdmin::API::Resources::User, label: 'User', value_label: :login
      integer :type, db_name: :t_type
      resource Transaction, name: :depends_on, label: 'Depends on'
      bool :urgent, db_name: :t_urgent
      integer :priority, db_name: :t_priority
      integer :success, db_name: :t_success
      integer :done, db_name: :t_done
      string :input, db_name: :t_param
      string :output, db_name: :t_output
      datetime :created_at
      datetime :started_at
      datetime :finished_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List transactions'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        output blacklist: %i(user type urgent priority input output)
        allow
      end

      def exec
        ::Transaction.where(with_restricted(transaction_chain_id: params[:transaction_chain_id]))
          .limit(input[:limit]).offset(input[:offset]).order('t_id DESC')
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
                id: params[:transaction_id]
            )
        )
      end

      def exec
        @trans
      end
    end
  end
end
