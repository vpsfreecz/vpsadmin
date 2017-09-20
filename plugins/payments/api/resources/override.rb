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
  end
end
