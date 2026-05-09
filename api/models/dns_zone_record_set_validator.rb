# frozen_string_literal: true

class DnsZoneRecordSetValidator
  REFERENCE_TYPES = %w[MX NS SRV].freeze

  Violation = Struct.new(:attribute, :message)

  def self.validate_record(record)
    new(record.dns_zone, candidate: record).validate_candidate.each do |violation|
      record.errors.add(violation.attribute, violation.message)
    end
  end

  def self.validate_zone(dns_zone, errors:, attribute:)
    new(dns_zone).validate_zone.each do |violation|
      errors.add(attribute, violation.message)
    end
  end

  def initialize(dns_zone, candidate: nil)
    @dns_zone = dns_zone
    @candidate = candidate
  end

  def validate_candidate
    return [] unless applicable?
    return [] unless served_record?(candidate)

    validate_record(candidate, records)
  end

  def validate_zone
    return [] unless applicable?

    records.flat_map { |record| validate_record(record, records) }.uniq do |violation|
      [violation.attribute, violation.message]
    end
  end

  protected

  attr_reader :dns_zone, :candidate

  def applicable?
    dns_zone && dns_zone.internal_source? && dns_zone.name.present?
  end

  def records
    @records ||= begin
      scope = dns_zone.dns_records.existing.where(enabled: true)
      scope = scope.where.not(id: candidate.id) if candidate&.persisted?

      ret = scope.to_a
      ret << candidate if served_record?(candidate)
      ret
    end
  end

  def served_record?(record)
    return false unless record
    return false if record.respond_to?(:confirmed) && record.confirmed == :confirm_destroy

    record.enabled != false
  end

  def validate_record(record, all_records)
    owner = local_owner(record)
    return [] unless owner

    ret = []

    case record.record_type
    when 'CNAME'
      ret << cname_at_apex_violation if apex?(owner)

      other = all_records.find { |r| !same_record?(r, record) && local_owner(r) == owner }
      ret << cname_coexistence_violation(owner) if other

      references = references_to(owner, all_records.reject { |r| same_record?(r, record) })
      ret << cname_reference_target_violation(owner, references) if references.any?

    when 'DS'
      ret << ds_at_apex_violation if apex?(owner)

      ret << cname_coexistence_violation(owner) if cname_at?(owner, all_records, excluding: record)

    else
      ret << cname_coexistence_violation(owner) if cname_at?(owner, all_records, excluding: record)
    end

    if REFERENCE_TYPES.include?(record.record_type)
      target = local_target(record)
      ret << target_cname_violation(target) if target && cname_at?(target, all_records)
    end

    ret
  end

  def local_owner(record)
    canonical_name(record.name)
  end

  def local_target(record)
    target =
      case record.record_type
      when 'MX', 'NS'
        record.content
      when 'SRV'
        record.content.to_s.split(/\s+/, 3)[2]
      end

    return if target.blank? || target == '.'

    canonical_name(target)
  end

  def references_to(owner, all_records)
    all_records.select do |record|
      REFERENCE_TYPES.include?(record.record_type) && local_target(record) == owner
    end
  end

  def cname_at?(owner, all_records, excluding: nil)
    all_records.any? do |record|
      record.record_type == 'CNAME' && !same_record?(record, excluding) && local_owner(record) == owner
    end
  end

  def canonical_name(name)
    value = name.to_s.strip.downcase
    return if value.empty?

    fqdn =
      if value == '@'
        origin
      elsif value.end_with?('.')
        value
      else
        "#{value}.#{origin}"
      end

    local_name?(fqdn) ? fqdn : nil
  end

  def local_name?(fqdn)
    fqdn == origin || fqdn.end_with?(".#{origin}")
  end

  def origin
    @origin ||= dns_zone.name.downcase
  end

  def apex?(owner)
    owner == origin
  end

  def same_record?(a, b)
    return false unless a && b

    if a.id && b.id
      a.instance_of?(b.class) && a.id == b.id
    else
      a.equal?(b)
    end
  end

  def cname_at_apex_violation
    Violation.new(:name, 'CNAME records are not allowed at the zone apex')
  end

  def ds_at_apex_violation
    Violation.new(:name, 'DS records are not allowed at the zone apex')
  end

  def cname_coexistence_violation(owner)
    Violation.new(:name, "CNAME records cannot coexist with other records at #{owner}")
  end

  def target_cname_violation(target)
    Violation.new(:content, "target #{target} must not be a CNAME")
  end

  def cname_reference_target_violation(owner, references)
    types = references.map(&:record_type).uniq.sort.join(', ')
    Violation.new(:name, "#{owner} is targeted by #{types} records and cannot be a CNAME")
  end
end
