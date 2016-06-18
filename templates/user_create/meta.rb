template do
  label        'User created'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
 
  lang :cs do
    subject    '[vpsFree.cz] Vytvoření členství <%= @user.login %>'
  end
  
  lang :en do
    subject    '[vpsFree.cz] Membership <%= @user.login %> confirmed'
  end
end
