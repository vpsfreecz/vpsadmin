template :alert_vps_dataset_over_quota do
  label 'VPS dataset over quota alert'

  lang :en do
    subject '[vpsAdmin] Dataset <%= @dataset.full_name %> is over quota'
  end
end
