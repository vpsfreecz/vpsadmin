template :user_failed_logins do
  label 'Failed login report'

  lang :en do
    subject '[vpsAdmin] Failed sign-in attempts for <%= @user.login %>'
  end
end
