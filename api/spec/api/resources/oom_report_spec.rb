# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::OomReport' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.location
    SpecSeed.other_location
    SpecSeed.environment
    SpecSeed.other_environment
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/oom_reports')
  end

  def show_path(id)
    vpath("/oom_reports/#{id}")
  end

  def usages_index_path(oom_id)
    vpath("/oom_reports/#{oom_id}/usages")
  end

  def usage_show_path(oom_id, usage_id)
    vpath("/oom_reports/#{oom_id}/usages/#{usage_id}")
  end

  def stats_index_path(oom_id)
    vpath("/oom_reports/#{oom_id}/stats")
  end

  def stat_show_path(oom_id, stat_id)
    vpath("/oom_reports/#{oom_id}/stats/#{stat_id}")
  end

  def tasks_index_path(oom_id)
    vpath("/oom_reports/#{oom_id}/tasks")
  end

  def task_show_path(oom_id, task_id)
    vpath("/oom_reports/#{oom_id}/tasks/#{task_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def oom_reports
    json.dig('response', 'oom_reports') || []
  end

  def oom_report
    json.dig('response', 'oom_report')
  end

  def usages
    json.dig('response', 'usages') || []
  end

  def usage
    json.dig('response', 'usage')
  end

  def stats
    json.dig('response', 'stats') || []
  end

  def stat
    json.dig('response', 'stat')
  end

  def tasks
    json.dig('response', 'tasks') || []
  end

  def task
    json.dig('response', 'task')
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_dataset_in_pool!(user:, pool:)
    dataset = Dataset.create!(
      name: "spec-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )
    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dataset_in_pool = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active
    )
  end

  let!(:seed_data) do
    base_time = Time.utc(2040, 1, 1, 12, 0, 0)

    vps_user = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'user-vps')
    vps_other = create_vps!(user: SpecSeed.other_user, node: SpecSeed.other_node, hostname: 'other-vps')
    vps_support = create_vps!(user: SpecSeed.support, node: SpecSeed.other_node, hostname: 'support-vps')

    rule_user_notify = OomReportRule.create!(
      vps: vps_user,
      action: :notify,
      cgroup_pattern: '/user/*',
      hit_count: 0
    )
    rule_other_ignore = OomReportRule.create!(
      vps: vps_other,
      action: :ignore,
      cgroup_pattern: '/other/*',
      hit_count: 0
    )
    rule_support_notify = OomReportRule.create!(
      vps: vps_support,
      action: :notify,
      cgroup_pattern: '/support/*',
      hit_count: 0
    )

    report_user_a = OomReport.create!(
      vps: vps_user,
      cgroup: '/user/a',
      invoked_by_pid: 10,
      invoked_by_name: 'invoker',
      killed_pid: 20,
      killed_name: 'killed',
      count: 1,
      created_at: base_time + 10,
      reported_at: base_time + 11,
      processed: true,
      ignored: false,
      oom_report_rule: rule_user_notify
    )

    report_user_b = OomReport.create!(
      vps: vps_user,
      cgroup: '/user/b',
      invoked_by_pid: 12,
      invoked_by_name: 'invoker-b',
      killed_pid: 22,
      killed_name: 'killed-b',
      count: 1,
      created_at: base_time + 20,
      reported_at: base_time + 21,
      processed: true,
      ignored: false,
      oom_report_rule: rule_user_notify
    )

    report_other = OomReport.create!(
      vps: vps_other,
      cgroup: '/other/a',
      invoked_by_pid: 30,
      invoked_by_name: 'invoker-o',
      killed_pid: 40,
      killed_name: 'killed-o',
      count: 1,
      created_at: base_time + 30,
      reported_at: base_time + 31,
      processed: true,
      ignored: false,
      oom_report_rule: rule_other_ignore
    )

    report_support = OomReport.create!(
      vps: vps_support,
      cgroup: '/support/a',
      invoked_by_pid: 50,
      invoked_by_name: 'invoker-s',
      killed_pid: 60,
      killed_name: 'killed-s',
      count: 1,
      created_at: base_time + 40,
      reported_at: base_time + 41,
      processed: true,
      ignored: false,
      oom_report_rule: rule_support_notify
    )

    report_user_unprocessed = OomReport.unscoped.create!(
      vps: vps_user,
      cgroup: '/user/unprocessed',
      invoked_by_pid: 11,
      invoked_by_name: 'invoker2',
      killed_pid: 21,
      killed_name: 'killed2',
      count: 1,
      created_at: base_time + 5,
      reported_at: nil,
      processed: false,
      ignored: false,
      oom_report_rule: nil
    )

    usage_user_primary = OomReportUsage.create!(
      oom_report: report_user_a,
      memtype: 'memory',
      usage: 100,
      limit: 200,
      failcnt: 1
    )

    OomReportUsage.create!(
      oom_report: report_user_a,
      memtype: 'swap',
      usage: 150,
      limit: 250,
      failcnt: 2
    )

    usage_other = OomReportUsage.create!(
      oom_report: report_other,
      memtype: 'memory',
      usage: 300,
      limit: 600,
      failcnt: 3
    )

    stat_user_primary = OomReportStat.create!(
      oom_report: report_user_a,
      parameter: 'rss',
      value: 123
    )

    OomReportStat.create!(
      oom_report: report_user_a,
      parameter: 'cache',
      value: 456
    )

    stat_other = OomReportStat.create!(
      oom_report: report_other,
      parameter: 'rss',
      value: 789
    )

    task_user_primary = OomReportTask.create!(
      oom_report: report_user_a,
      name: 'ruby',
      host_pid: 1000,
      vps_pid: 2000,
      host_uid: 0,
      vps_uid: 1000,
      tgid: 1000,
      total_vm: 10_000,
      rss: 5_000,
      rss_anon: 1_000,
      rss_file: 2_000,
      rss_shmem: 3_000,
      pgtables_bytes: 4096,
      swapents: 0,
      oom_score_adj: 0
    )

    OomReportTask.create!(
      oom_report: report_user_a,
      name: 'nginx',
      host_pid: 1100,
      vps_pid: 2100,
      host_uid: 0,
      vps_uid: 1001,
      tgid: 1100,
      total_vm: 20_000,
      rss: 7_000,
      rss_anon: 2_000,
      rss_file: 3_000,
      rss_shmem: 1_000,
      pgtables_bytes: 8192,
      swapents: 0,
      oom_score_adj: 0
    )

    task_other = OomReportTask.create!(
      oom_report: report_other,
      name: 'python',
      host_pid: 2100,
      vps_pid: 2200,
      host_uid: 0,
      vps_uid: 1002,
      tgid: 2100,
      total_vm: 30_000,
      rss: 9_000,
      rss_anon: 4_000,
      rss_file: 4_000,
      rss_shmem: 1_000,
      pgtables_bytes: 16_384,
      swapents: 0,
      oom_score_adj: 0
    )

    {
      base_time: base_time,
      vps_user: vps_user,
      vps_other: vps_other,
      vps_support: vps_support,
      rule_user_notify: rule_user_notify,
      rule_other_ignore: rule_other_ignore,
      rule_support_notify: rule_support_notify,
      report_user_a: report_user_a,
      report_user_b: report_user_b,
      report_other: report_other,
      report_support: report_support,
      report_user_unprocessed: report_user_unprocessed,
      usage_user_primary: usage_user_primary,
      usage_other: usage_other,
      stat_user_primary: stat_user_primary,
      stat_other: stat_other,
      task_user_primary: task_user_primary,
      task_other: task_other
    }
  end

  def base_time
    seed_data.fetch(:base_time)
  end

  def vps_user
    seed_data.fetch(:vps_user)
  end

  def vps_other
    seed_data.fetch(:vps_other)
  end

  def vps_support
    seed_data.fetch(:vps_support)
  end

  def rule_user_notify
    seed_data.fetch(:rule_user_notify)
  end

  def report_user_a
    seed_data.fetch(:report_user_a)
  end

  def report_user_b
    seed_data.fetch(:report_user_b)
  end

  def report_other
    seed_data.fetch(:report_other)
  end

  def report_support
    seed_data.fetch(:report_support)
  end

  def report_user_unprocessed
    seed_data.fetch(:report_user_unprocessed)
  end

  def usage_user_primary
    seed_data.fetch(:usage_user_primary)
  end

  def usage_other
    seed_data.fetch(:usage_other)
  end

  def stat_user_primary
    seed_data.fetch(:stat_user_primary)
  end

  def stat_other
    seed_data.fetch(:stat_other)
  end

  def task_user_primary
    seed_data.fetch(:task_user_primary)
  end

  def task_other
    seed_data.fetch(:task_other)
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows only processed reports for the user' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_user_a.id, report_user_b.id)
    end

    it 'shows only processed reports for the support user' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_support.id)
    end

    it 'shows all processed reports for admins' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(
        report_user_a.id,
        report_user_b.id,
        report_other.id,
        report_support.id
      )
    end

    it 'orders reports by created_at desc' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to eq([report_user_b.id, report_user_a.id])
    end

    it 'allows admin to filter by user' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { user: SpecSeed.user.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_user_a.id, report_user_b.id)
    end

    it 'ignores non-admin user filter' do
      as(SpecSeed.user) { json_get index_path }
      ids_a = oom_reports.map { |row| row['id'] }

      as(SpecSeed.user) { json_get index_path, oom_report: { user: SpecSeed.other_user.id } }
      ids_b = oom_reports.map { |row| row['id'] }

      expect(ids_b).to eq(ids_a)
    end

    it 'filters by vps' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { vps: vps_user.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_user_a.id, report_user_b.id)

      as(SpecSeed.user) { json_get index_path, oom_report: { vps: vps_other.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(oom_reports).to eq([])
    end

    it 'filters by node for admins' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { node: SpecSeed.other_node.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_other.id, report_support.id)
    end

    it 'filters by location for admins' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { location: SpecSeed.location.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_user_a.id, report_user_b.id)
    end

    it 'filters by environment for admins' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { environment: SpecSeed.other_environment.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_other.id, report_support.id)
    end

    it 'filters by oom_report_rule' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { oom_report_rule: rule_user_notify.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to contain_exactly(report_user_a.id, report_user_b.id)
    end

    it 'filters by cgroup' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { cgroup: '/user/a' } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to eq([report_user_a.id])
    end

    it 'filters by since and until' do
      as(SpecSeed.admin) do
        json_get index_path,
                 oom_report: {
                   since: (base_time + 9).iso8601,
                   until: (base_time + 10).iso8601
                 }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to eq([report_user_a.id])
    end

    it 'supports limit and from_id pagination' do
      as(SpecSeed.admin) { json_get index_path, oom_report: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(oom_reports.length).to eq(1)

      boundary = OomReport.maximum(:id)
      as(SpecSeed.admin) { json_get index_path, oom_report: { from_id: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = oom_reports.map { |row| row['id'] }
      expect(ids).to all(be < boundary)
    end

    it 'supports meta count' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(OomReport.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(report_user_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their processed report' do
      as(SpecSeed.user) { json_get show_path(report_user_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(oom_report['id']).to eq(report_user_a.id)
    end

    it 'prevents users from showing other user reports' do
      as(SpecSeed.user) { json_get show_path(report_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any report' do
      as(SpecSeed.admin) { json_get show_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(oom_report['id']).to eq(report_other.id)
    end

    it 'returns status false for unknown reports' do
      missing = OomReport.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'does not show unprocessed reports' do
      as(SpecSeed.admin) { json_get show_path(report_user_unprocessed.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end

  describe 'Usage Index' do
    it 'rejects unauthenticated access' do
      json_get usages_index_path(report_user_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists usages for the user report' do
      as(SpecSeed.user) { json_get usages_index_path(report_user_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = usages.map { |row| row['id'] }
      expect(ids).to include(usage_user_primary.id)
      expect(usages.length).to eq(2)
      expect(usages.first.keys).to include('id', 'memtype', 'usage', 'limit', 'failcnt')
    end

    it 'returns empty list for other user reports' do
      as(SpecSeed.user) { json_get usages_index_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(usages).to eq([])
    end

    it 'allows admins to list usages for other users' do
      as(SpecSeed.admin) { json_get usages_index_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = usages.map { |row| row['id'] }
      expect(ids).to include(usage_other.id)
    end

    it 'supports usage limit pagination' do
      as(SpecSeed.admin) { json_get usages_index_path(report_user_a.id), usage: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(usages.length).to eq(1)
    end

    it 'supports usage meta count' do
      as(SpecSeed.admin) { json_get usages_index_path(report_user_a.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(
        OomReportUsage.where(oom_report: report_user_a).count
      )
    end
  end

  describe 'Usage Show' do
    it 'rejects unauthenticated access' do
      json_get usage_show_path(report_user_a.id, usage_user_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their usage' do
      as(SpecSeed.user) { json_get usage_show_path(report_user_a.id, usage_user_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(usage['id']).to eq(usage_user_primary.id)
    end

    it 'prevents users from showing other user usage' do
      as(SpecSeed.user) { json_get usage_show_path(report_other.id, usage_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show other user usage' do
      as(SpecSeed.admin) { json_get usage_show_path(report_other.id, usage_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(usage['id']).to eq(usage_other.id)
    end

    it 'returns status false for mismatched parent id' do
      as(SpecSeed.admin) { json_get usage_show_path(report_user_a.id, usage_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'returns status false for unknown usage id' do
      missing = OomReportUsage.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get usage_show_path(report_user_a.id, missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end

  describe 'Stat Index' do
    it 'rejects unauthenticated access' do
      json_get stats_index_path(report_user_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists stats for the user report' do
      as(SpecSeed.user) { json_get stats_index_path(report_user_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = stats.map { |row| row['id'] }
      expect(ids).to include(stat_user_primary.id)
      expect(stats.length).to eq(2)
      expect(stats.first.keys).to include('id', 'parameter', 'value')
    end

    it 'returns empty list for other user reports' do
      as(SpecSeed.user) { json_get stats_index_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(stats).to eq([])
    end

    it 'allows admins to list stats for other users' do
      as(SpecSeed.admin) { json_get stats_index_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = stats.map { |row| row['id'] }
      expect(ids).to include(stat_other.id)
    end

    it 'supports stat limit pagination' do
      as(SpecSeed.admin) { json_get stats_index_path(report_user_a.id), stat: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(stats.length).to eq(1)
    end

    it 'supports stat meta count' do
      as(SpecSeed.admin) { json_get stats_index_path(report_user_a.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(
        OomReportStat.where(oom_report: report_user_a).count
      )
    end
  end

  describe 'Stat Show' do
    it 'rejects unauthenticated access' do
      json_get stat_show_path(report_user_a.id, stat_user_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their stat' do
      as(SpecSeed.user) { json_get stat_show_path(report_user_a.id, stat_user_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(stat['id']).to eq(stat_user_primary.id)
    end

    it 'prevents users from showing other user stat' do
      as(SpecSeed.user) { json_get stat_show_path(report_other.id, stat_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show other user stat' do
      as(SpecSeed.admin) { json_get stat_show_path(report_other.id, stat_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(stat['id']).to eq(stat_other.id)
    end

    it 'returns status false for mismatched parent id' do
      as(SpecSeed.admin) { json_get stat_show_path(report_user_a.id, stat_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'returns status false for unknown stat id' do
      missing = OomReportStat.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get stat_show_path(report_user_a.id, missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end

  describe 'Task Index' do
    it 'rejects unauthenticated access' do
      json_get tasks_index_path(report_user_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists tasks for the user report' do
      as(SpecSeed.user) { json_get tasks_index_path(report_user_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = tasks.map { |row| row['id'] }
      expect(ids).to include(task_user_primary.id)
      expect(tasks.length).to eq(2)
      expect(tasks.first.keys).to include(
        'id', 'name', 'host_pid', 'vps_pid', 'vps_uid', 'tgid', 'total_vm',
        'rss', 'rss_anon', 'rss_file', 'rss_shmem', 'pgtables_bytes',
        'swapents', 'oom_score_adj'
      )
    end

    it 'returns empty list for other user reports' do
      as(SpecSeed.user) { json_get tasks_index_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(tasks).to eq([])
    end

    it 'allows admins to list tasks for other users' do
      as(SpecSeed.admin) { json_get tasks_index_path(report_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      ids = tasks.map { |row| row['id'] }
      expect(ids).to include(task_other.id)
    end

    it 'supports task limit pagination' do
      as(SpecSeed.admin) { json_get tasks_index_path(report_user_a.id), task: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(tasks.length).to eq(1)
    end

    it 'supports task meta count' do
      as(SpecSeed.admin) { json_get tasks_index_path(report_user_a.id), _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(
        OomReportTask.where(oom_report: report_user_a).count
      )
    end
  end

  describe 'Task Show' do
    it 'rejects unauthenticated access' do
      json_get task_show_path(report_user_a.id, task_user_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their task' do
      as(SpecSeed.user) { json_get task_show_path(report_user_a.id, task_user_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(task['id']).to eq(task_user_primary.id)
    end

    it 'prevents users from showing other user task' do
      as(SpecSeed.user) { json_get task_show_path(report_other.id, task_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show other user task' do
      as(SpecSeed.admin) { json_get task_show_path(report_other.id, task_other.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(task['id']).to eq(task_other.id)
    end

    it 'returns status false for mismatched parent id' do
      as(SpecSeed.admin) { json_get task_show_path(report_user_a.id, task_other.id) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end

    it 'returns status false for unknown task id' do
      missing = OomReportTask.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get task_show_path(report_user_a.id, missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end
end
