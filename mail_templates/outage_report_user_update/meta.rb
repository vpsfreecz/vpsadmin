template :outage_report_role_event do
  label        'User outage report update'
  from         'podpora@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :en do
    subject    "Re: [Outage Report] <%= @o.planned ? 'Planned' : 'Unplanned' %> outage - <%= @o.outage_entities.map { |e| e.real_name }.join(',') %> - <%= @o.begins_at.strftime('%Y-%m-%d %H:%M') %>"
  end
end
