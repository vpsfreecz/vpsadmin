class Dataset < ActiveRecord::Base
  belongs_to :user
  has_many :dataset_in_pools
  has_many :snapshots

  has_ancestry cache_depth: true

  validates :name, format: {
      with: /\A[a-zA-Z0-9][a-zA-Z0-9_\-:\.]{0,254}\z/,
      message: "'%{value}' is not a valid dataset name"
  }

  before_save :cache_full_name

  include Confirmable

  def resolve_full_name
    if parent_id
      "#{parent.resolve_full_name}/#{name}"
    else
      name
    end
  end

  def hypervisor_mountpoint
    mountpoint = dataset_in_pools
      .joins(:pool)
      .where(pools: {role: Pool.roles[:hypervisor]}).pluck(:mountpoint).first

    # FIXME: This is not nice at all. Dataset should make NO ASSUMPTIONS
    # as to the VPS root prefix.
    mountpoint.sub!(/\/vz\/root\/\d+/, '') if mountpoint

    mountpoint
  end

  protected
  def cache_full_name
    self.full_name = resolve_full_name
  end
end
