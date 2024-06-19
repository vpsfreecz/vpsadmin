class DatasetPropertyHistory < ApplicationRecord
  belongs_to :dataset_property

  def name
    dataset_property.name
  end
end
