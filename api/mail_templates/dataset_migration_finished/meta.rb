template :dataset_migration_finished do
  label 'Dataset migration finished'

  lang :en do
    subject '[vpsAdmin] Dataset <%= @dataset.full_name %> migration finished'
  end
end
