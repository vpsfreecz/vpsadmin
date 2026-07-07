class OutageEntity < ApplicationRecord
  ENTITY_TYPES = {
    'vpsAdmin' => 'vpsadmin',
    'Cluster' => 'cluster',
    'Environment' => 'environment',
    'Location' => 'location',
    'Node' => 'node'
  }.freeze

  belongs_to :outage

  def entity_type
    ENTITY_TYPES.fetch(name, 'custom')
  end

  def real_name
    case name
    when 'vpsAdmin'
      Component.find(row_id).label

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
    real_name
  rescue ActiveRecord::RecordNotFound
    row_id ? row_id.to_s : name
  end
end
