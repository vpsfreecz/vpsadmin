template :payment_accepted do
  label 'Payment accepted'

  lang :en do
    subject '[vpsAdmin] Accepted payment <%= @user.login %> - <%= @payment.received_amount %> <%= @payment.received_currency.to_s.upcase %>'
  end
end
