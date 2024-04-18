module VpsAdmin::API::Plugins::Payments
  class Metrics < VpsAdmin::API::Plugin::MetricsBase
    def setup
      @user_monthly_payment = add_metric(
        :gauge,
        :user_monthly_payment,
        docstring: 'Expected monthly payment'
      )

      @user_paid_until = add_metric(
        :gauge,
        :user_paid_until,
        docstring: 'Time until the user account is paid for'
      )
    end

    def compute
      acc = user.user_account
      return if acc.nil?

      @user_monthly_payment.set(acc.monthly_payment)
      @user_paid_until.set(acc.paid_until) if acc.paid_until
    end
  end
end
