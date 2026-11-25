import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test-1-node.nix;
    creds = import ../../configs/nixos/vpsadmin-credentials.nix;
    nodeSeed = seed.nodes.node;
    common =
      (import ./common.nix {
        adminUserId = seed.adminUser.id;
        node1Id = nodeSeed.id;
      })
      + (import ../supervisor/common.nix {
        adminUserId = seed.adminUser.id;
        node1Id = nodeSeed.id;
        nodeDomain = nodeSeed.domain;
        rabbitmqVhost = creds.rabbitmq.vhost;
        rabbitSupervisorUser = creds.rabbitmq.users.supervisor;
      });
  in
  {
    name = "alerts-rtnl-exposure";
    description = "Verify synthetic duration evidence, current read APIs, daily gains and observe-mode reporting.";
    tags = [
      "ci"
      "vpsadmin"
      "alerts"
      "vps"
      "supervisor"
    ];
    machines = import ../../machines/cluster/1-node.nix args;

    testScripts.default = {
      description = "Verify synthetic duration evidence, current read APIs, daily gains and observe-mode reporting.";
      attempts = 1;
      script = common + ''
        before(:suite) do
          setup_alerts_cluster(services, node)
          services.wait_for_service('vpsadmin-supervisor.service')
        end

        def rtnl_state(services, vps_id, epoch)
          services.api_ruby_json(code: <<~RUBY)
            vps = Vps.find(#{Integer(vps_id)})
            reports = IncidentReport.where(vps_id: vps.id).where(codename: 'rtnl_latency')
            report = reports.order(:id).last
            receipts = VpsEvidenceEvent.where(node_id: vps.node_id, signal: 'rtnl_latency', producer_epoch: #{epoch.inspect})
            puts JSON.dump(
              reports: reports.count, snapshot: report&.evidence_snapshot, report_id: report&.id,
              reported: !report&.reported_at.nil?, source: report&.attributes&.slice('source_kind', 'source_node_id', 'source_action', 'vps_action'),
              matched: report&.incident_policy_evaluations&.matched&.pluck(:policy_key),
              receipt_count: receipts.count, facts: receipts.first&.facts,
              live_credit_us: VpsEvidenceInterval.live.where(vps_id: vps.id, signal: 'rtnl_latency').sum(:credit_us),
              live_acceptances: VpsEvidenceInterval.live.where(vps_id: vps.id, signal: 'rtnl_latency').where.not(accepted_at: nil).count,
              copy_acceptances: report&.vps_evidence_intervals&.where&.not(accepted_at: nil)&.count,
              saved_credit_us: report&.vps_evidence_intervals&.sum(:credit_us),
              accepted_us: VpsEvidenceState.find_by(vps_id: vps.id, signal: 'rtnl_latency')&.accepted_us,
              actions: vps.vps_incident_actions.count,
              notices: IncidentReport.where(vps_id: vps.id).where(source_kind: 'incident_policy_notice').count,
              lifecycle_transactions: Transaction.where(vps_id: vps.id, handle: [1001, 1002, 1003]).count
            )
          RUBY
        end

        describe 'synthetic RTNL exposure through the node event transport' do
          it 'reports saved intervals in observe mode without a VPS action' do
            owner = create_test_user(services, login: 'evidence-member', password: 'secret123')
            stranger = create_test_user(services, login: 'evidence-other', password: 'secret123')
            [owner, stranger].each do |created|
              wait_for_task_chains_done(services, { 'chain_ids' => Array(created['chain_id']).compact }, label: 'evidence member setup')
            end
            member_auth = { auth: 'basic', user: owner.fetch('login'), password: 'secret123' }
            stranger_auth = { auth: 'basic', user: stranger.fetch('login'), password: 'secret123' }
            vps_id = create_vps(services, admin_user_id: owner.fetch('user_id'), node_id: node1_id,
              hostname: 'rtnl-exposure', start: true).fetch('id')
            wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: true)
            settings = services.api_ruby_json(code: <<~RUBY)
              { threshold_seconds: 2, window_seconds: 60, repeat_seconds: 60, enabled: true }.each do |name, value|
                SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: name.to_s).update!(value: value)
              end
              SysConfig.find_by!(category: 'webui', name: 'base_url').update!(value: 'http://webui.vpsadmin.test/')
              puts JSON.dump(mode: SysConfig.get(:incident_policy_rtnl_latency, :mode))
            RUBY
            expect(settings.fetch('mode')).to eq('observe')
            services.clear_mailpit
            # Require a genuinely fresh daemon status; do not manufacture it in the DB.
            wait_until_block_succeeds(name: 'fresh running VPS status for RTNL reporting') do
              readiness = services.api_ruby_json(code: <<~RUBY)
                vps = Vps.find(#{vps_id})
                status = vps.vps_current_status
                puts JSON.dump(ready: status && status.status && status.is_running && status.updated_at > Time.now.utc - 10)
              RUBY
              expect(readiness.fetch('ready')).to be(true)
              true
            end

            event = JSON.parse(${builtins.toJSON (builtins.readFile ../../../libnodectld/spec/fixtures/vps_evidence_v1.json)})
            _, output = node.succeeds(<<~SH)
              ruby -rjson -ropen3 -rsecurerandom <<'RUBY'
              event = JSON.parse(#{JSON.dump(event).inspect})
              output, status = Open3.capture2('osctl', '-j', 'ct', 'show', '-o', 'pool,id,state,group_path,init_pid', #{vps_id.to_s.inspect})
              raise 'Unable to read guest container identity' unless status.success?
              ct = JSON.parse(output)
              raise 'Container is not running' unless ct.fetch('state') == 'running'
              pid = Integer(ct.fetch('init_pid'))
              ticks = Integer(File.read('/proc/' + pid.to_s + '/stat').split(') ', 2).last.split.fetch(19))
              opts = event.fetch('opts')
              mono_delta = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - opts.fetch('observed_mono_us')
              utc_delta = (Time.now.utc.to_r * 1_000_000).to_i - opts.fetch('observed_at_us')
              opts['boot_id'] = File.read('/proc/sys/kernel/random/boot_id').strip
              opts['producer_epoch'] = SecureRandom.hex(16)
              opts['batch_id'] = opts.fetch('signal') + ':' + opts.fetch('producer_epoch') + ':' + opts.fetch('sequence').to_s
              opts['observed_at_us'] += utc_delta
              %w[observed_mono_us coverage_started_mono_us].each { |key| opts[key] += mono_delta }
              target = opts.fetch('targets').first
              target.merge!('pool' => ct.fetch('pool'), 'id' => ct.fetch('id'),
                'run' => { 'group_path' => ct.fetch('group_path'), 'init_pid' => pid, 'init_start_time_ticks' => ticks })
              %w[window_from_mono_us window_to_mono_us].each { |key| target[key] += mono_delta }
              opts.fetch('segments').each do |segment|
                 %w[from_mono_us to_mono_us].each { |key| segment[key] += mono_delta }
                %w[probe_started_mono_us probe_completed_mono_us coverage_started_mono_us].each { |key| segment['evidence'][key] += mono_delta }
                %w[from_at_us to_at_us].each { |key| segment[key] += utc_delta }
              end
              File.write('/run/rtnl-exposure-integration.json', JSON.dump('events' => [event]) + 10.chr)
              puts JSON.dump(event)
              RUBY
            SH
            event = JSON.parse(output.lines.last)
            epoch = event.fetch('opts').fetch('producer_epoch')
            before = rtnl_state(services, vps_id, epoch)
            node.succeeds('osctl event broadcast < /run/rtnl-exposure-integration.json')
            state = nil
            wait_until_block_succeeds(name: 'one RTNL report accepted through CtMonitor and supervisor') do
              state = rtnl_state(services, vps_id, epoch)
              expect(state).to include('reports' => 1, 'receipt_count' => 1, 'reported' => true)
              true
            end
            expect(state).to include('accepted_us' => 2_000_000, 'live_credit_us' => 2_000_000,
              'saved_credit_us' => 2_000_000, 'live_acceptances' => 1, 'copy_acceptances' => 0, 'matched' => ['rtnl_latency'], 'facts' => event.fetch('opts'),
              'actions' => 0, 'notices' => 0, 'lifecycle_transactions' => before.fetch('lifecycle_transactions'))
            expect(state.fetch('source')).to include('source_kind' => 'node_oomd_evidence',
              'source_node_id' => node1_id, 'source_action' => 'none', 'vps_action' => 'none')
            snapshot = state.fetch('snapshot')
            expect(snapshot).to include('window_seconds' => 60, 'threshold_seconds' => 2, 'repeat_seconds' => 60,
              'signal' => 'rtnl_latency', 'representation' => 'qualified_duration',
              'condition' => { 'measurement' => 'rtnl_latency', 'operator' => 'gt', 'value' => 1_000_000, 'unit' => 'microseconds' }, 'credit_us' => 2_000_000, 'qualification_interval_us' => 5_000_000,
              'interval_count' => 1, 'window_complete' => false)
            expect(Time.iso8601(snapshot.fetch('window_to')) - Time.iso8601(snapshot.fetch('window_from'))).to eq(60)
            expect(snapshot.fetch('evaluated_at')).to eq(snapshot.fetch('window_to'))

            _, own_live = services.vpsadminctl.succeeds(args: ['vps.evidence', 'index', vps_id.to_s], opts: member_auth)
            expect(own_live.fetch('_meta')).to include('configuration_valid' => true, 'unavailable_signals' => [])
            expect(own_live.fetch('evidence').find { |row| row.fetch('signal') == 'rtnl_latency' }).to include(
              'credit_us' => 2_000_000, 'window_seconds' => 60, 'reporting_enabled' => true)
            _, own_overview = services.vpsadminctl.succeeds(args: ['vps_evidence', 'index'], opts: member_auth, parameters: { limit: 1 })
            expect(own_overview.fetch('_meta')).to include('total_count' => 1, 'next_offset' => nil)
            expect(own_overview.fetch('vps_evidence').first.fetch('vps').fetch('id')).to eq(vps_id)
            expect(own_overview.fetch('vps_evidence').first).not_to have_key('user')
            _, admin_overview = services.vpsadminctl.succeeds(args: ['vps_evidence', 'index'], parameters: { vps: vps_id, limit: 1 })
            expect(admin_overview.fetch('vps_evidence').first).to include('credit_us' => 2_000_000,
              'user' => include('id' => owner.fetch('user_id')))
            _, denied_overview = services.vpsadminctl.succeeds(args: ['vps_evidence', 'index'], opts: stranger_auth)
            expect(denied_overview.fetch('vps_evidence')).to eq([])
            expect(denied_overview.fetch('_meta').fetch('total_count')).to eq(0)
            services.vpsadminctl.fails(args: ['vps.evidence', 'index', vps_id.to_s], opts: stranger_auth)

            report_id = state.fetch('report_id')
            _, page = services.vpsadminctl.succeeds(args: ['incident_report.evidence_interval', 'index', report_id.to_s], parameters: { limit: 1 })
            expect(page.fetch('_meta')).to include('available' => true, 'total_count' => 1, 'offset' => 0,
              'limit' => 1, 'next_offset' => nil, 'window_complete' => false, 'window_seconds' => 60,
              'threshold_seconds' => 2, 'repeat_seconds' => 60, 'credit_us' => 2_000_000)
            expect(page.fetch('evidence_intervals').length).to eq(1)
            interval = page.fetch('evidence_intervals').first
            segment = event.fetch('opts').fetch('segments').first
            %w[from to].each do |endpoint|
              expected = Time.at(Rational(segment.fetch(endpoint + '_at_us'), 1_000_000)).utc.iso8601(6)
              expect(interval.fetch(endpoint + '_at')).to eq(expected)
            end
            expect(interval).to include('credit_us' => 2_000_000, 'measurement' => 'rtnl_latency', 'peak_unit' => 'microseconds', 'peak_value' => 3_000_000, 'peak_is_lower_bound' => false)
            _, empty = services.vpsadminctl.succeeds(args: ['incident_report.evidence_interval', 'index', report_id.to_s], parameters: { offset: 1, limit: 1 })
            expect(empty.fetch('evidence_intervals')).to eq([])
            expect(empty.fetch('_meta')).to include('offset' => 1, 'total_count' => 1, 'next_offset' => nil)
            _, policies = services.vpsadminctl.succeeds(args: ['vps.incident_policy', 'index', vps_id.to_s])
            policy_rows = policies.fetch('incident_policies')
            expect(policy_rows.find { |row| row.fetch('key') == 'rtnl_latency' }).to include(
              'count_7d' => 1, 'count_30d' => 1, 'effective_mode' => 'observe', 'warning_limit' => 3, 'stop_limit' => 10)
            expect(policy_rows.find { |row| row.fetch('key') == 'oomd' }).to include('count_7d' => 0, 'count_30d' => 0)

            detail_url = "http://webui.vpsadmin.test/?page=incidents&action=show&id=#{report_id}"
            expect_delivered_mail(services, to: 'evidence-member@example.test', text_includes: [
              'accumulated 2.0 s', 'window of 60 s', 'threshold was 2 s', 'repeat after 60 s',
              'credited time 2.0 s', 'peak RTNL latency 3.0 s', 'Contributing intervals shown: 1 of 1',
              interval.fetch('from_at'), interval.fetch('to_at'), detail_url
            ])
            expect(mail_log_count(services, 'vps_incident_report')).to eq(1)
            mail_ids = services.mailpit_messages.fetch('messages').map { |row| row.fetch('ID') }
            expect(mail_ids.length).to eq(1)
            # Broadcast acceptance is not a DB acknowledgement. Observe bounded
            # resend stability; focused model specs cover the consumed duplicate branch.
            node.succeeds('osctl event broadcast < /run/rtnl-exposure-integration.json')
            observation_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            5.times do
              sleep(1)
              expect(rtnl_state(services, vps_id, epoch)).to eq(state)
              _, current_policies = services.vpsadminctl.succeeds(args: ['vps.incident_policy', 'index', vps_id.to_s])
              expect(current_policies.fetch('incident_policies')).to eq(policy_rows)
              expect(mail_log_count(services, 'vps_incident_report')).to eq(1)
              expect(services.mailpit_messages.fetch('messages').map { |row| row.fetch('ID') }).to match_array(mail_ids)
              wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: true)
            end
            puts JSON.dump(resend_observation_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - observation_started)
            daily = run_api_task(services, klass: 'VpsAdmin::API::Tasks::Mail', method: :daily_report, env: { VPSADMIN_LANG: 'en' })
            expect(daily.fetch('chain_ids')).not_to be_empty
            wait_for_task_chains_done(services, daily, label: 'accepted evidence daily report')
            expect_delivered_mail(services, to: ${builtins.toJSON seed.adminUser.email}, subject_prefix: '[vpsAdmin] Daily report ', text_includes: [
              'VPS evidence credit gained', '2 s accepted; VPS / ownership periods: 1.',
              "Saved owner ##{owner.fetch('user_id')}", 'Repeated or overlapping contributions are counted only once.',
              "Current VPS details: http://webui.vpsadmin.test/?page=adminvps&action=info&veid=#{vps_id}"
            ])
            expect(mail_log_count(services, 'daily_report')).to eq(1)
            expect(rtnl_state(services, vps_id, epoch)).to eq(state)

          end
        end
      '';
    };
  }
)
