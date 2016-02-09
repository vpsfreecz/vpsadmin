module VpsAdmin::API::Resources
  class Transaction < HaveAPI::Resource
    desc 'Access transactions linked in a chain'
    model ::Transaction

    params(:all) do
      id :id
      resource TransactionChain
      resource Node, label: 'Node', value_label: :name
      resource User, label: 'User', value_label: :login
      integer :type, db_name: :t_type
      string :name
      resource VPS, label: 'VPS', value_label: :hostname
      resource Transaction, name: :depends_on, label: 'Depends on', value_label: :name
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
        resource TransactionChain, label: 'Transaction chain', value_label: :name
        resource Node, label: 'Node', value_label: :name
        integer :type, db_name: :t_type
        integer :success, db_name: :t_success
        string :done, db_name: :t_done, choices: ::Transaction.t_dones.keys
      end

      output(:object_list) do
        use :all
        patch :limit, fill: true
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        output blacklist: %i(user type urgent priority input output)
        allow
      end

      def query
        q = ::Transaction.where(with_restricted)

        q = q.where(transaction_chain: input[:transaction_chain]) if input[:transaction_chain]
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
        @trans = ::Transaction.find_by!(with_restricted(
            t_id: params[:transaction_id]
        ))
      end

      def exec
        @trans
      end
    end
  end
end
