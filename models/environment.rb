class Environment < ActiveRecord::Base
  has_many :locations
  has_paper_trail

  validates :label, :domain, presence: true
  validates :domain, format: {
    with: /[0-9a-zA-Z\-\.]{3,63}/,
    message: 'invalid format'
  }

  def fqdn
    domain
  end

  def vps_count
    locations.all.inject(0) do |sum, loc|
      loc.nodes.all.each do |node|
        sum += node.vpses.count
      end

      sum
    end
  end
end
