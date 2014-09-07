class StorageExport < ActiveRecord::Base
  self.table_name = 'storage_export'

  belongs_to :user, foreign_key: :member_id
  belongs_to :storage_root, foreign_key: :root_id
  has_many :vps_mounts

  has_paper_trail

  validates :member_id, :root_id, :dataset, :path, :quota, :data_type,
            presence: true
  validates :member_id, :root_id, :quota, :used, :avail, numericality: {
      only_integer: true
  }
  validates :default, inclusion: {
      in: %w(no member vps),
      message: '%{value} is not a valid value'
  }
  validates :data_type, inclusion: {
      in: %w(data backup),
      message: '%{value} is not a valid data type'
  }

  # Create default exports for +obj+.
  # +obj+ can be an instance of User or Vps.
  def self.create_default_exports(obj, depend: nil)
    type = obj.is_a?(User) ? :member : :vps
    mapping = {}
    last_id = nil

    self.where(default: type).each do |e|
      export = self.new(e.attributes)
      export.id = nil
      export.default = 'no'

      if export.member_id.nil? || export.member_id == 0
        export.member_id = obj.id if obj.is_a?(User)
        export.member_id = obj.user_id if obj.is_a?(Vps)
      end

      resolve_vars(export.dataset, obj)
      resolve_vars(export.path, obj)

      if export.storage_root.storage_layout == 'per_member'
        export.dataset = "#{export.member_id}/#{export.dataset}"
        export.path = "#{export.member_id}/#{export.path}"
      end

      export.save!

      last_id = Transactions::Storage::CreateDataset.fire_chained(depend, export)

      mapping[e.id] = export.id
    end

    [mapping, last_id]
  end

  def self.resolve_vars(str, obj)
    str.gsub!(/%member_id%/, (obj.is_a?(User) ? obj.id : obj.user_id).to_s)
    str.gsub!(/%veid%/, obj.id.to_s) if obj.is_a?(Vps)
  end
end
