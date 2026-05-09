template :user_new_token do
  label 'New user token'

  lang :en do
    subject '[vpsAdmin] New access token for <%= @user.login %>'
  end
end
