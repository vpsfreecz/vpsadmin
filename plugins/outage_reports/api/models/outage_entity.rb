class OutageEntity < ActiveRecord::Base
  belongs_to :outage

  def real_name
    case name
    when 'Cluster'
      'Cluster-wide'

    when 'Environment'
      Environment.find(row_id).label

    when 'Location'
      Location.find(row_id).label

    when 'Node'
      Node.find(row_id).domain_name

    else
      name
    end
  end

  def label
    case name
    when 'Cluster'
      'All systems within the cluster'

    when 'Environment'
      "Environment #{real_name}"

    when 'Location'
      "Location #{real_name}"

    when 'Node'
      "Node #{real_name}"

    else
      real_name
    end

  rescue ActiveRecord::RecordNotFound
    "#{name} #{row_id}"
  end
end
