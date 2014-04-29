class Environment < ActiveRecord::Base
  has_many :locations
  has_paper_trail

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
