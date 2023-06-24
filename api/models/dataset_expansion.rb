class DatasetExpansion < ::ActiveRecord::Base
  belongs_to :dataset
  has_many :dataset_expansion_histories
  enum state: %i(active resolved)
  validates :original_refquota, :added_space, numericality: {greater_than: 0}
end
