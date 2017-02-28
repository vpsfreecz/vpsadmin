class OutageEntity < ActiveRecord::Base
  belongs_to :outage

  def label
    case name
    when 'Cluster'
      'All systems within the cluster'

    when 'Environment'
      "Environment #{Environment.find(row_id).label}"

    when 'Location'
      "Location #{Location.find(row_id).label}"

    when 'Node'
      "Node #{Node.find(row_id).domain_name}"

    else
      name
    end

  rescue ActiveRecord::RecordNotFound
    "#{name} #{row_id}"
  end
end
