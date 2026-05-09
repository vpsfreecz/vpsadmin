template :dataset_migration_begun do
  label 'Dataset migration begun'

  lang :en do
    subject '[vpsAdmin] Dataset <%= @dataset.full_name %> migration started'
  end
end
