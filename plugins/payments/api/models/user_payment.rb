class UserPayment < ActiveRecord::Base
  belongs_to :incoming_payment
  belongs_to :user
  belongs_to :accounted_by, class_name: 'User'

  validates :user_id, :amount, :from_date, :to_date, presence: true

  def self.create!(attrs)
    payment = new(attrs)
    payment.accounted_by = ::User.current

    if attrs[:incoming_payment]
      payment.amount = payment.incoming_payment.converted_amount
    end

    monthly = payment.user.user_account.monthly_payment

    if payment.amount % monthly != 0
      payment.errors.add(
        :amount,
        "not a multiple of the monthly payment (#{monthly})"
      )
      raise ActiveRecord::RecordInvalid, payment
    end

    VpsAdmin::API::Plugins::Payments::TransactionChains::Create.fire(payment)
  end

  def received_amount
    incoming_payment_id ? incoming_payment.received_amount : amount
  end

  def received_currency
    if incoming_payment_id
      incoming_payment.received_currency
    else
      SysConfig.get(:plugin_payments, :default_currency)
    end
  end
end

TransactionChains::Mail::DailyReport.connect_hook(:send) do |ret, from, now|
  t = now.strftime('%Y-%m-%d %H:%M:%S')

  ret[:payments] ||= {}
  ret[:payments][:accepted] = ::UserPayment.where(
    'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
  ).order('user_payments.created_at, user_payments.user_id')
  ret
end
