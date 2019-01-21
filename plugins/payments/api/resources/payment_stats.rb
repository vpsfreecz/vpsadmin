module VpsAdmin::API::Resources
  class PaymentStats < HaveAPI::Resource
    desc 'View payment statistics'
    singular true

    class EstimateIncome < HaveAPI::Action
      desc 'Estimate income for selected month and duration'
      auth false

      input(:hash) do
        integer :year, required: true
        integer :month, required: true
        string :select, choices: %w(exactly_until all_until), required: true
        integer :duration, required: true
      end

      output(:hash) do
        integer :user_count
        integer :estimated_income
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        y = input[:year]
        m = input[:month]
        d = input[:duration]

        q = ::UserAccount
          .joins(:user)
          .where(users: {object_state: [
            ::User.object_states[:active],
            ::User.object_states[:suspended],
          ]})

        q =
          case input[:select]
          when 'exactly_until'
            q
              .where('YEAR(paid_until) = ?', y)
              .where('MONTH(paid_until) = ?', m)
          when 'all_until'
            q
              .where('YEAR(paid_until) <= ?', y)
              .where('MONTH(paid_until) <= ?', m)
          else
            fail 'programming error'
          end

        {
          user_count: q.count,
          estimated_income: q.sum("monthly_payment") * d,
        }
      end
    end
  end
end
