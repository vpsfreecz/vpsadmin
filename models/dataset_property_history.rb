class DatasetPropertyHistory < ActiveRecord::Base
  belongs_to :dataset_property

  def name
    dataset_property.name
  end
end
