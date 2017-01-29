module VpsAdmin::API::Resources
  class IncomingPayment < HaveAPI::Resource
    desc "Browse incoming payments"
    model ::IncomingPayment

    params(:filters) do
      string :state, choices: ::IncomingPayment.states.keys.map(&:to_s)
    end

    params(:all) do
      id :id
      string :transaction_id
      use :filters
      datetime :date
      integer :amount
      string :currency
      integer :src_amount
      string :src_currency
      string :account_name
      string :user_ident
      string :user_message
      string :vs
      string :ks
      string :ss
      string :transaction_type
      string :comment
      datetime :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List incoming payments'

      input do
        use :filters
        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::IncomingPayment.all
        q = q.where(state: ::IncomingPayment.states[input[:state]]) if input[:state]
        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset]).order(
            'incoming_payments.date DESC'
        )
      end
    end
    
    class Show < HaveAPI::Actions::Default::Show
      desc 'Show incoming payment'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end
      
      def prepare
        @payment = ::IncomingPayment.find(params['incoming_payment_id'])
      end

      def exec
        @payment
      end
    end
  end
end
