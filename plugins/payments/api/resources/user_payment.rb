module VpsAdmin::API::Resources
  class UserPayment < HaveAPI::Resource
    desc "Manage user's payment settings"
    model ::UserPayment

    params(:writable) do
      resource VpsAdmin::API::Resources::IncomingPayment, value_label: :transaction_id
      resource VpsAdmin::API::Resources::User, value_label: :login
      integer :amount
    end

    params(:all) do
      id :id
      use :writable
      resource VpsAdmin::API::Resources::User, name: :accounted_by, value_label: :login
      datetime :from_date
      datetime :to_date
      datetime :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user payments'

      input do
        resource VpsAdmin::API::Resources::User
        resource VpsAdmin::API::Resources::User, name: :accounted_by
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i[user accounted_by]
        allow
      end

      def query
        q = ::UserPayment.where(with_restricted)

        %i[user accounted_by].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_desc_pagination(with_includes(query)).order(
          'user_payments.created_at DESC, user_payments.id DESC'
        )
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user payment'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @payment = ::UserPayment.find_by!(with_restricted(
                                            id: params['user_payment_id']
                                          ))
      end

      def exec
        @payment
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a user payment'
      blocking true

      input do
        use :writable
        patch :user, required: true
        patch :amount, number: { min: 1 }
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        error!('Provide amount or incoming payment') if !input[:amount] && !input[:incoming_payment]

        @chain, payment = ::UserPayment.create!(input)
        payment
      rescue ActiveRecord::RecordInvalid => e
        error!('Create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique
        error!('Create failed: this incoming payment is already assigned')
      rescue ::UserAccount::AccountDisabled => e
        error!(e.message)
      end

      def state_id
        @chain.id
      end
    end
  end
end
