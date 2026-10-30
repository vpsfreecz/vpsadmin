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

    testScript = common + ''
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

      def reconcile_incident_actions(services)
        response = run_api_task(services, klass: 'VpsAdmin::API::Tasks::IncidentReport', method: :process)
        wait_for_task_chains_done(services, response, label: 'incident reconciliation')
      end

      describe 'registered memory-pressure incident escalation' do
        it 'stops once, retries failed mail independently, and permits manual restart during cooldown' do
          vps_id = create_alert_vps(services, hostname: 'incident-escalation', start: true).fetch('id')
          vps_exec(node, vps_id: vps_id, command: 'echo preserved > /root/incident-data')
          services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}
            SysConfig.find_by!(category: 'incident_policy_oomd', name: 'mode').update!(value: 'enforce')
            TransactionChains::Vps::Update.fire(Vps.find(#{vps_id}), { incident_policy: 'oomd', incident_warning_limit_override: 1, incident_stop_limit_override: 2 })
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
            reconcile_incident_actions(services)
            reconcile_incident_actions(services)
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
          expect_delivered_mail(services, to: ${builtins.toJSON seed.adminUser.email}, text_includes: ['was stopped after repeated resource incidents'])
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
            expect(shown.fetch('vps').fetch('incident_count_30d')).to eq(3)
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
          expect(current.fetch('incident_count_7d')).to eq(0)
          expect(current.fetch('incident_count_30d')).to eq(0)
          expect(current.fetch('incident_last_warning_at')).to be_nil
          expect(current.fetch('incident_last_stop_at')).to eq(previous.fetch('incident_last_stop_at'))
          expect(current.fetch('incident_next_stop_allowed_at')).to eq(previous.fetch('incident_next_stop_allowed_at'))
          _, history = services.vpsadminctl.succeeds(args: ['incident_report', 'list'],
            opts: { auth: 'basic', user: 'incident-transferred-owner', password: 'secret123' },
            parameters: { vps: vps_id, codename: 'oomd' })
          expect(history.fetch('incident_reports')).to eq([])
          _, audit = services.vpsadminctl.succeeds(args: ['incident_report', 'list'],
            parameters: { vps: vps_id, codename: 'oomd' })
          expect(audit.fetch('incident_reports').size).to eq(3)
          wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: true)
          _, retained = vps_exec(node, vps_id: vps_id, command: 'cat /root/incident-data')
          expect(retained.strip).to eq('preserved')
        end
      end
    '';
  }
)
