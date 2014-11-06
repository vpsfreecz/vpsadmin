class MaintenanceLock < ActiveRecord::Base
  belongs_to :user

  def lock!
    self.class.transaction do
      tmp = self.class.find_by(
          class_name: class_name,
          row_id: row_id,
          active: true
      )

      return false if tmp

      self.active = true
      save!
    end
  end

  def unlock!
    self.active = false
    save!
  end
end
