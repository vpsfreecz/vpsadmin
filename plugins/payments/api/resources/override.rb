module VpsAdmin::API::Resources
  class User
    params(:payments) do
      integer :monthly_payment, label: 'Monthly payment'
      datetime :paid_until, label: 'Paid until'
    end

    class Index
      output(:object_list) do
        use :payments
      end
    end

    class Show
      output do
        use :payments
      end
    end

    class Current
      output do
        use :payments
      end
    end

    class GetPaymentInstructions < HaveAPI::Action
      route '{%{resource}_id}/get_payment_instructions'
      http_method :get

      output(:hash) do
        string :instructions
      end

      authorize do |u|
        allow
      end

      def exec
        if current_user.role != :admin && current_user.id != params[:user_id].to_i
          error('access denied')
        end

        {instructions: ::User.find(params[:user_id]).user_account.payment_instructions}
      end
    end
  end
end
