template do
  label        'User account revived'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Znovuvytvoření členství <%= @user.login %>'
end
