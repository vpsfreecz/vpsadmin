class OutageHandler < ActiveRecord::Base
  belongs_to :outage
  belongs_to :user

  before_validation :set_name

  protected
  def set_name
    return if !full_name.nil? && !full_name.empty?
    self.full_name = user.full_name
  end
end
