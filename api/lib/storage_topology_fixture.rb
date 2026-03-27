# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module StorageTopologyFixture
  VERSION = 1

  REQUIRED_FIXTURE_KEYS = %w[version generated_at metadata report diagnostic].freeze
  REQUIRED_REPORT_KEYS = %w[db zfs].freeze
  REQUIRED_DB_KEYS = %w[trees branches entries].freeze
  REQUIRED_ZFS_KEYS = %w[origins clones].freeze

  module_function

  def normalize_backup_topology_report(report)
    normalized = deep_copy(report)
    db = normalized.fetch('db')
    zfs = normalized.fetch('zfs')

    db.fetch('trees').sort_by! do |row|
      [row.fetch('index'), row.fetch('id')]
    end

    db.fetch('branches').sort_by! do |row|
      [row.fetch('tree_index'), row.fetch('index'), row.fetch('id')]
    end

    db.fetch('entries').sort_by! do |row|
      [
        row.fetch('tree_index'),
        row.fetch('branch_index'),
        row.fetch('snapshot_name'),
        row.fetch('entry_id')
      ]
    end

    zfs['origins'] = zfs.fetch('origins').sort.to_h
    zfs['clones'] = zfs.fetch('clones').sort.to_h do |name, clones|
      [name, Array(clones).sort]
    end

    normalized
  end

  def topology_fixture_payload(report, metadata: {}, generated_at: nil)
    normalized = normalize_backup_topology_report(report)

    {
      'version' => VERSION,
      'generated_at' => fixture_timestamp(generated_at),
      'metadata' => metadata,
      'report' => normalized,
      'diagnostic' => delete_order_diagnostic(normalized)
    }
  end

  def write_topology_fixture(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{JSON.pretty_generate(payload)}\n")
    path
  end

  def load_topology_fixture(path)
    JSON.parse(File.read(path))
  end

  def zfs_leaf_snapshot_names(report)
    report.fetch('zfs').fetch('clones')
          .select { |_, clones| clones.empty? }
          .keys
          .map { |path| path.split('@', 2).last }
          .uniq
          .sort
  end

  def db_leaf_candidate_snapshot_names(report)
    report.fetch('db').fetch('entries')
          .select { |row| row.fetch('reference_count').to_i == 0 }
          .map { |row| row.fetch('snapshot_name') }
          .uniq.sort
  end

  def delete_order_diagnostic(report)
    zfs_leaf_snapshots = zfs_leaf_snapshot_names(report)
    db_candidate_snapshots = db_leaf_candidate_snapshot_names(report)

    {
      'zfs_leaf_snapshots' => zfs_leaf_snapshots,
      'db_candidate_snapshots' => db_candidate_snapshots,
      'db_but_not_zfs' => (db_candidate_snapshots - zfs_leaf_snapshots).sort,
      'zfs_but_not_db' => (zfs_leaf_snapshots - db_candidate_snapshots).sort
    }
  end

  def delete_order_leaf_contract(report)
    diagnostic = delete_order_diagnostic(report)

    {
      'zfs_leaf_snapshots' => diagnostic.fetch('zfs_leaf_snapshots'),
      'db_candidate_snapshots' => diagnostic.fetch('db_candidate_snapshots'),
      'db_but_not_zfs' => diagnostic.fetch('db_but_not_zfs'),
      'zfs_but_not_db' => diagnostic.fetch('zfs_but_not_db'),
      'leaf_sets_match' => diagnostic.fetch('db_but_not_zfs').empty? &&
        diagnostic.fetch('zfs_but_not_db').empty?
    }
  end

  def delete_order_leaf_contract_from_fixture(path)
    fixture = load_topology_fixture(path)
    delete_order_leaf_contract(fixture.fetch('report'))
  end

  def validate_fixture(fixture)
    errors = []

    unless fixture.is_a?(Hash)
      return {
        errors: ['fixture must be a JSON object'],
        normalized_report: nil,
        diagnostic: nil,
        contract: nil,
        expected_leaf_sets_match: nil
      }
    end

    missing_fixture_keys = REQUIRED_FIXTURE_KEYS.reject do |key|
      fixture.has_key?(key)
    end
    unless missing_fixture_keys.empty?
      errors << "fixture missing keys: #{missing_fixture_keys.join(', ')}"
    end

    version = fixture['version']
    if version != VERSION
      errors << "fixture version must be #{VERSION}, got #{version.inspect}"
    end

    generated_at = fixture['generated_at']
    begin
      Time.iso8601(generated_at.to_s)
    rescue ArgumentError
      errors << "fixture generated_at must be ISO8601, got #{generated_at.inspect}"
    end

    metadata = fixture['metadata']
    unless metadata.is_a?(Hash)
      errors << "fixture metadata must be an object, got #{metadata.class}"
      metadata = {}
    end

    report = fixture['report']
    errors.concat(validate_report_shape(report))

    normalized_report = nil
    diagnostic = nil
    contract = nil
    expected_leaf_sets_match = metadata.fetch('expected_leaf_sets_match', nil)

    if errors.empty?
      normalized_report = normalize_backup_topology_report(report)
      diagnostic = delete_order_diagnostic(normalized_report)
      contract = delete_order_leaf_contract(normalized_report)

      if report != normalized_report
        errors << 'fixture report is not normalized'
      end

      if fixture['diagnostic'] != diagnostic
        errors << 'fixture diagnostic does not match report'
      end

      unless expected_leaf_sets_match.nil? ||
             contract.fetch('leaf_sets_match') == expected_leaf_sets_match
        errors << 'fixture expected_leaf_sets_match does not match leaf contract'
      end
    end

    {
      errors: errors,
      normalized_report: normalized_report,
      diagnostic: diagnostic,
      contract: contract,
      expected_leaf_sets_match: expected_leaf_sets_match
    }
  end

  def validate_fixture!(fixture)
    result = validate_fixture(fixture)
    return result if result.fetch(:errors).empty?

    raise ArgumentError, result.fetch(:errors).join('; ')
  end

  def fixture_summary(fixture)
    result = validate_fixture!(fixture)

    {
      'generated_at' => fixture.fetch('generated_at'),
      'metadata' => fixture.fetch('metadata'),
      'leaf_sets_match' => result.fetch(:contract).fetch('leaf_sets_match'),
      'db_candidate_snapshots' => result.fetch(:contract).fetch('db_candidate_snapshots'),
      'zfs_leaf_snapshots' => result.fetch(:contract).fetch('zfs_leaf_snapshots'),
      'db_but_not_zfs' => result.fetch(:contract).fetch('db_but_not_zfs'),
      'zfs_but_not_db' => result.fetch(:contract).fetch('zfs_but_not_db')
    }
  end

  def validate_report_shape(report)
    errors = []

    unless report.is_a?(Hash)
      return ['fixture report must be an object']
    end

    missing_report_keys = REQUIRED_REPORT_KEYS.reject { |key| report.has_key?(key) }
    unless missing_report_keys.empty?
      errors << "fixture report missing keys: #{missing_report_keys.join(', ')}"
      return errors
    end

    db = report['db']
    zfs = report['zfs']

    unless db.is_a?(Hash)
      errors << 'fixture report.db must be an object'
      return errors
    end

    unless zfs.is_a?(Hash)
      errors << 'fixture report.zfs must be an object'
      return errors
    end

    missing_db_keys = REQUIRED_DB_KEYS.reject { |key| db.has_key?(key) }
    unless missing_db_keys.empty?
      errors << "fixture report.db missing keys: #{missing_db_keys.join(', ')}"
    end

    missing_zfs_keys = REQUIRED_ZFS_KEYS.reject { |key| zfs.has_key?(key) }
    unless missing_zfs_keys.empty?
      errors << "fixture report.zfs missing keys: #{missing_zfs_keys.join(', ')}"
    end

    errors << 'fixture report.db.trees must be an array' unless db['trees'].is_a?(Array)
    errors << 'fixture report.db.branches must be an array' unless db['branches'].is_a?(Array)
    errors << 'fixture report.db.entries must be an array' unless db['entries'].is_a?(Array)
    errors << 'fixture report.zfs.origins must be an object' unless zfs['origins'].is_a?(Hash)
    errors << 'fixture report.zfs.clones must be an object' unless zfs['clones'].is_a?(Hash)

    errors
  end

  def fixture_timestamp(value)
    return Time.now.utc.iso8601 if value.nil?

    Time.parse(value.to_s).utc.iso8601
  end
  private_class_method :fixture_timestamp

  def deep_copy(obj)
    JSON.parse(JSON.generate(obj))
  end
  private_class_method :deep_copy
end
