class DatasetExpansion < ::ActiveRecord::Base
  belongs_to :vps
  belongs_to :dataset
  has_many :dataset_expansion_histories
  enum state: %i(active resolved)
  validates :original_refquota, :added_space, numericality: {greater_than: 0}

  # @return [DatasetExpansion]
  def self.create_for_expanded!(dataset_in_pool, **attrs)
    exp = new(attrs)

    dataset_in_pool.acquire_lock do
      ActiveRecord::Base.transaction do
        exp.save!

        exp.dataset_expansion_histories.create!(
          added_space: exp.added_space,
          original_refquota: exp.original_refquota,
          new_refquota: dataset_in_pool.refquota,
          admin: ::User.current,
        )

        exp.dataset.update!(dataset_expansion: exp)
      end
    end

    exp
  end

  # @return [Integer]
  def expansion_count
    dataset_expansion_histories.where('added_space > 0').count
  end
end
