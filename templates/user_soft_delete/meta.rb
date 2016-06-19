template do
  label        'User account enters soft_delete'
  from         'podpora@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Ukončení členství <%= @user.login %>'
  end

  lang :en do
    subject    '[vpsFree.cz] Membership <%= @user.login %> terminated'
  end
end
