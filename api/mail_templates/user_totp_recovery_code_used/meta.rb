template :user_totp_recovery_code_used do
  label 'TOTP recovery code used'

  lang :en do
    subject '[vpsAdmin] Recovery code used for <%= @user.login %>'
  end
end
