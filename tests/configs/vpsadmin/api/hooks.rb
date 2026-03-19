DatasetInPool.connect_hook(:create) do |ret, dataset_in_pool|
  next ret unless dataset_in_pool.pool.role == 'hypervisor'

  backup_pool = Pool.where(role: 'backup', is_open: true).where('max_datasets > 0').take
  next ret if backup_pool.nil?

  dataset_in_pool.update!(
    min_snapshots: 1,
    max_snapshots: 1
  )

  begin
    backup = DatasetInPool.create(
      dataset: dataset_in_pool.dataset,
      pool: backup_pool
    )

    append(Transactions::Storage::CreateDataset, args: backup) do
      create(backup)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  ret
end
