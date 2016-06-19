template do
  label        'Snapshot download ready'
  from         'podpora@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Archiv je připraven ke stažení'
  end
  
  lang :en do
    subject    '[vpsFree.cz] Download is ready'
  end
end
