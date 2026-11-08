module VpsAdmin::API::Resources
  class UserAccount < HaveAPI::Resource
    desc "Manage user's payment settings"
    model ::UserAccount

    params(:editable) do
      integer :monthly_payment
      datetime :paid_until, nullable: true
    end

    params(:all) do
      id :id, db_name: :user_id
      use :editable
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user accounts'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::UserAccount.all
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user account'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @acc = ::UserAccount.find_by!(user_id: path_params['user_account_id'])
      end

      def exec
        @acc
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update user account'

      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        acc = ::UserAccount.find_by!(user_id: path_params['user_account_id'])

        acc.class.transaction do
          acc.acquire_lock do
            acc.lock!
            acc.update!(input)
            update_expiration(acc) if input.has_key?(:paid_until)
          end
        end

        acc
      rescue ActiveRecord::RecordInvalid => e
        error!('Update failed', e.record.errors.to_hash)
      end

      private

      def update_expiration(acc)
        acc.user.set_expiration(acc.paid_until, reason: 'Paid until date has changed.')
        return unless acc.saved_change_to_paid_until?

        previous_expiration, new_expiration = acc.saved_change_to_paid_until
        ::UserPayment.new(
          user: acc.user,
          accounted_by: ::User.current,
          expiration_change: true,
          from_date: previous_expiration,
          to_date: new_expiration
        ).save!
      end
    end
  end
end
