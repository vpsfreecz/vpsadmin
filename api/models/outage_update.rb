class OutageUpdate < ActiveRecord::Base
  belongs_to :outage
  belongs_to :reported_by, class_name: 'User'
  has_many :outage_translations

  enum state: %i(staged announced closed cancelled)
  enum outage_type: %i(tbd restart reset network performance maintenance)

  after_initialize :load_translations
  before_validation :set_name

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
    outage_translations.find_by!(language: ::User.current.language).summary

  rescue ActiveRecord::RecordNotFound
    # It seems that self.outage_translation is cached, so force a new query
    any = ::OutageTranslation.where(outage_update: self).take
    any ? any.summary : ''
  end

  def description
    outage_translations.find_by!(language: ::User.current.language).description

  rescue ActiveRecord::RecordNotFound
    # It seems that self.outage_translation is cached, so force a new query
    any = ::OutageTranslation.where(outage_update: self).take
    any ? any.description : ''
  end

  def load_translations
    outage_translations.each do |tr|
      %i(summary description).each do |param|
        define_singleton_method("#{tr.language.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end

  protected
  def set_name
    return if (!reporter_name.nil? && !reporter_name.empty?) || reported_by.nil?
    self.reporter_name = reported_by.full_name
  end
end
