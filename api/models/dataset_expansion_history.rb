class DatasetExpansionHistory < ::ActiveRecord::Base
  belongs_to :dataset_expansion
  belongs_to :admin, class_name: 'User', foreign_key: :admin_id
end
