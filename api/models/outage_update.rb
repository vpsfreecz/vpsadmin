class OutageUpdate < ActiveRecord::Base
  belongs_to :outage
  belongs_to :reported_by, class_name: 'User'
  has_many :outage_translations

  enum state: %i(staged announced closed cancelled)
  enum outage_type: %i(tbd restart reset network performance maintenance)

  # Set the origin for attribute changes
  def origin=(attrs)
    @origin = attrs
    @origin['state'] = self.class.states.invert[@origin['state']]
    @origin['outage_type'] = self.class.outage_types.invert[@origin['outage_type']]
  end

  # @yieldparam attribute [Symbol]
  # @yieldparam old_value [any]
  # @yieldparam new_value [any]
  def each_change
    %i(begins_at finished_at duration state outage_type).each do |attr|
      old = @origin[attr.to_s]
      new = send(attr)
      yield(attr, old, new) if !new.nil? && new != old
    end
  end

  def summary
    outage_translations.find(language: ::User.current.language).summary

  rescue ActiveRecord::RecordNotFound
    any = outage_translations.take
    any ? any.summary : ''
  end

  def description
    outage_translations.find(language: ::User.current.language).description

  rescue ActiveRecord::RecordNotFound
    any = outage_translations.take
    any ? any.description: ''
  end
end
