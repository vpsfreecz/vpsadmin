template do
  label        'User account resumed'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Obnovení členství <%= @user.login %>'
end
