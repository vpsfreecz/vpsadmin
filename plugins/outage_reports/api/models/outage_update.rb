class OutageUpdate < ApplicationRecord
  belongs_to :outage
  belongs_to :reported_by, class_name: 'User'
  has_many :outage_translations

  enum :state, %i[staged announced resolved cancelled]
  enum :impact_type, %i[
    tbd
    system_restart
    system_reset
    network
    performance
    unavailability
    export
  ]

  after_initialize :load_translations
  before_validation :set_name

  # Set the origin for attribute changes
  attr_writer :origin

  def outage_type
    outage.outage_type
  end

  # @yieldparam attribute [Symbol]
  # @yieldparam old_value [any]
  # @yieldparam new_value [any]
  def each_change
    %i[begins_at finished_at duration state impact_type].each do |attr|
      old = @origin[attr.to_s]
      new = send(attr)
      yield(attr, old, new) if !new.nil? && new != old
    end
  end

  %i[summary description].each do |attr|
    define_method(attr) do
      return @translation.send(attr) if @translation

      begin
        @translation = outage_translations.find_by!(language: ::User.current.language)
        @translation.send(attr)
      rescue ActiveRecord::RecordNotFound
        # It seems that self.outage_translation is cached, so force a new query
        @translation = ::OutageTranslation.where(outage_update: self).take
        @translation ? @translation.send(attr) : ''
      end
    end
  end

  def load_translations
    ::OutageTranslation.joins(
      'RIGHT JOIN languages ON languages.id = outage_translations.language_id'
    ).where(
      outage_update_id: id
    ).each do |tr|
      %i[summary description].each do |param|
        define_singleton_method("#{tr.language.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end

  def to_hash
    ret = {
      id:,
      changes: {},
      translations: {}
    }

    each_change do |attr, old, new|
      case attr
      when :begins_at, :finished_at
        ret[:changes][attr] = { from: old && old.iso8601, to: new && new.iso8601 }

      when :impact_type
        ret[:changes][:type] = { from: old, to: new }

      else
        ret[:changes][attr] = { from: old, to: new }
      end
    end

    outage_translations.reload.each do |tr|
      ret[:translations][tr.language.code] = {
        summary: tr.summary,
        description: tr.description
      }
    end

    ret
  end

  protected

  def set_name
    return if (!reporter_name.nil? && !reporter_name.empty?) || reported_by.nil?

    self.reporter_name = reported_by.full_name
  end
end
