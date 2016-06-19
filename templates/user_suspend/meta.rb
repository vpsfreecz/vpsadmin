template do
  label        'User account suspended'
  from         'podpora@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Pozastavení členství <%= @user.login %>'
  end

  lang :en do
    subject    '[vpsFree.cz] Membership <%= @user.login %> suspended'
  end
end
