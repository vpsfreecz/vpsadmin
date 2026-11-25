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
    name = "alerts-incident-escalation";
    description = "Verify repeated daemon events, physical stop, independent mail retry, restart and ownership transfer.";
    tags = [
      "ci"
      "vpsadmin"
      "alerts"
      "vps"
      "supervisor"
    ];
    machines = import ../../machines/cluster/1-node.nix args;

    testScripts.default.script = common + ''
      before(:suite) do
        setup_alerts_cluster(services, node)
        services.wait_for_service('vpsadmin-supervisor.service')
      end

      def incident_action(services, vps_id)
        services.api_ruby_json(code: <<~RUBY)
          action = VpsIncidentAction.where(vps_id: #{Integer(vps_id)}, kind: 'stop').order(:id).last
          puts JSON.dump(action: action&.attributes, stop_count: VpsIncidentAction.where(vps_id: #{Integer(vps_id)}, kind: 'stop').count)
        RUBY
      end

      def reconcile_incident_actions(services, expect_smtp_failure: false)
        response = run_api_task(services, klass: 'VpsAdmin::API::Tasks::IncidentReport', method: :process)
        return wait_for_task_chains_done(services, response, label: 'incident reconciliation') unless expect_smtp_failure

        response.fetch('chain_ids').each do |chain_id|
          expect(wait_for_vps_chain_done(services, chain_id)).to eq(services.class::CHAIN_STATES[:failed])
          failures = chain_failure_details(services, chain_id)
          expect(failures).not_to be_empty
          expect(failures).to all(include('handle' => 9001, 'done' => 1, 'status' => 0))
          expect(failures.map { |row| row.dig('output', 'execute', 'error') }).to all(include('Errno::ECONNREFUSED'))
        end
      end

      describe 'registered memory-pressure incident escalation' do
        it 'stops once, retries failed mail independently, and permits manual restart during cooldown' do
          vps_id = create_alert_vps(services, hostname: 'incident-escalation', start: true).fetch('id')
          vps_exec(node, vps_id: vps_id, command: 'echo preserved > /root/incident-data')
          ordinary = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}
            vps = Vps.find(#{vps_id})
            report = IncidentReport.create!(vps: vps, user: vps.user, filed_by: User.current,
              codename: 'fixture_abuse', subject: 'Ordinary category', text: 'Imported fixture evidence', detected_at: Time.now)
            puts JSON.dump(matched: report.incident_policy_evaluations.matched.order(:policy_key).pluck(:policy_key),
              counts: report.incident_policy_evaluations.matched.order(:policy_key).map { |row| row.snapshot.fetch('context').fetch('count_30d') },
              actions: vps.vps_incident_actions.count)
          RUBY
          expect(ordinary).to include('matched' => %w[manual_category manual_content], 'counts' => [1, 1], 'actions' => 0)
          services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}
            SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'enforce')
            IncidentEscalation.update_policy!(Vps.find(#{vps_id}), 'oomd', warning_limit_override: 1, stop_limit_override: 2)
            puts JSON.dump(ok: true)
          RUBY
          first_time = Time.now.to_i - 2
          publish = lambda do |time|
            publish_supervisor_payload(services, routing_key: 'vps_events', payload: {
              id: vps_id, time: time, type: 'oomd', opts: { action: 'restart' }
            })
          end
          publish.call(first_time)
          expect_delivered_mail(services, to: ${builtins.toJSON seed.adminUser.email}, text_includes: ['has repeatedly triggered our resource protection system'])

          services.succeeds('nixos-container run mailer -- systemctl stop mailpit.service')
          begin
            publish.call(first_time + 1)
            publish.call(first_time + 1) # transport duplicate
            wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: false)
            reconcile_incident_actions(services, expect_smtp_failure: true)
            reconcile_incident_actions(services, expect_smtp_failure: true)
            failed = incident_action(services, vps_id)
            expect(failed.fetch('action').fetch('state')).to eq('completed')
            expect(failed.fetch('action').fetch('mail_state')).to eq('failed')
            expect(failed.fetch('stop_count')).to eq(1)
            _, stopped = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
            expect(stopped.fetch('vps').fetch('autostart_enable')).to be(false)
          ensure
            services.succeeds('nixos-container run mailer -- systemctl start mailpit.service')
            services.wait_for_mailpit
          end
          services.api_ruby_json(code: <<~RUBY)
            VpsIncidentAction.where(vps_id: #{vps_id}, kind: 'stop').update_all(retry_after: nil)
            puts JSON.dump(ok: true)
          RUBY
          reconcile_incident_actions(services)
          expect_delivered_mail(services, to: ${builtins.toJSON seed.adminUser.email}, text_includes: ['was stopped after repeated incidents'])
          expect(incident_action(services, vps_id).fetch('stop_count')).to eq(1)

          _, started = services.vpsadminctl.succeeds(args: ['vps', 'start', vps_id.to_s])
          chain_id = action_state_id(started)
          expect(wait_for_vps_chain_done(services, chain_id)).to eq(services.class::CHAIN_STATES[:done])
          wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: true)
          _, data = vps_exec(node, vps_id: vps_id, command: 'cat /root/incident-data')
          expect(data.strip).to eq('preserved')
          publish.call(Time.now.to_i)
          wait_until_block_succeeds(name: 'new cooldown incident counted') do
            _, shown = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
            _, policies = services.vpsadminctl.succeeds(args: ['vps.incident_policy', 'index', vps_id.to_s])
            expect(policies.fetch('incident_policies').find { |policy| policy.fetch('key') == 'oomd' }.fetch('count_30d')).to eq(3)
            expect(shown.fetch('vps').fetch('autostart_enable')).to be(true)
            true
          end
          reconcile_incident_actions(services)
          expect(incident_action(services, vps_id).fetch('stop_count')).to eq(1)
          wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: true)

          _, before_transfer = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
          previous = before_transfer.fetch('vps')
          new_owner = create_test_user(services, login: 'incident-transferred-owner', password: 'secret123')
          expect_chain_done(services, new_owner, label: 'create incident transfer owner')
          transfer = vps_update(services, admin_user_id: admin_user_id, vps_id: vps_id,
            attrs: { user_id: new_owner.fetch('user_id') })
          expect_chain_done(services, transfer, label: 'transfer incident VPS')
          reconcile_incident_actions(services)
          proof = services.api_ruby_json(code: <<~RUBY)
            vps = Vps.find(#{vps_id})
            chown = Transaction.find_by!(transaction_chain_id: #{transfer.fetch('chain_id')}, handle: 3041)
            puts JSON.dump(epoch_matches_finish: vps.incident_accounting_since == chown.finished_at,
              transfer_reconciled: vps.incident_owner_transfer_chain_id.nil?)
          RUBY
          expect(proof).to include('epoch_matches_finish' => true, 'transfer_reconciled' => true)
          _, after_transfer = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
          current = after_transfer.fetch('vps')
          expect(current.fetch('user').fetch('id')).to eq(new_owner.fetch('user_id'))
          expect(current.fetch('incident_accounting_since')).not_to be_nil
          _, policies = services.vpsadminctl.succeeds(args: ['vps.incident_policy', 'index', vps_id.to_s])
          expect(policies.fetch('incident_policies').find { |policy| policy.fetch('key') == 'oomd' }).to include(
            'count_7d' => 0, 'count_30d' => 0, 'last_warning_at' => nil
          )
          expect(current.fetch('incident_last_stop_at')).to eq(previous.fetch('incident_last_stop_at'))
          expect(current.fetch('incident_next_stop_allowed_at')).to eq(previous.fetch('incident_next_stop_allowed_at'))
          _, history = services.vpsadminctl.succeeds(args: ['incident_report', 'list'],
            opts: { auth: 'basic', user: 'incident-transferred-owner', password: 'secret123' },
            parameters: { vps: vps_id, policy_key: 'oomd' })
          expect(history.fetch('incident_reports')).to eq([])
          _, audit = services.vpsadminctl.succeeds(args: ['incident_report', 'list'],
            parameters: { vps: vps_id, policy_key: 'oomd' })
          ordinary, notices = audit.fetch('incident_reports').partition { |report| report['notice_kind'].nil? }
          expect(ordinary.size).to eq(3)
          expect(notices.map { |report| report.fetch('notice_kind') }).to contain_exactly('warning', 'stop_completed')
          expect(notices.map { |report| report.fetch('trigger_incident_report_id') } - ordinary.map { |report| report.fetch('id') }).to be_empty
          wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: true)
          _, retained = vps_exec(node, vps_id: vps_id, command: 'cat /root/incident-data')
          expect(retained.strip).to eq('preserved')
        end
      end
    '';
  }
)
