import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    servicesAddress = "192.168.10.10";
    nodeFqdn = "${nodeSeed.domain}.${seed.environment.domain}";
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
    machines = import ../../machines/cluster/1-node.nix (
      args
      // {
        extraModules = {
          services =
            { lib, ... }:
            {
              vpsadmin = {
                download-mounter.enable = lib.mkForce true;
                frontend.download-mounter.test.domain = "download.vpsadmin.test";
                waitOnline.api.url = lib.mkForce "http://127.0.0.1:9292/";
              };
            };

          nodes.node =
            { ... }:
            {
              networking.firewall.enable = false;
              services.nfs.server.enable = true;
            };
        };
      }
    );
  in
  {
    name = "client-snapshot-download";

    description = ''
      Download an archive-format snapshot through vpsadminctl and verify full
      and resumed downloads against the mounted download frontend.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "client"
    ];

    inherit machines;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def download_node_fqdn
        ${builtins.toJSON nodeFqdn}
      end

      def download_services_address
        ${builtins.toJSON servicesAddress}
      end

      def download_healthcheck_file
        '_vpsadmin-download-healthcheck'
      end

      def create_download_mounter_token(services, admin_user_id:)
        services.api_ruby_json(code: <<~RUBY)
          admin = User.find(#{Integer(admin_user_id)})
          token = Token.get!(valid_to: nil)
          user_agent = UserAgent.find_or_create!('client-snapshot-download')
          session = UserSession.create!(
            user: admin,
            admin: admin,
            auth_type: 'token',
            api_ip_addr: '127.0.0.1',
            client_ip_addr: '127.0.0.1',
            user_agent: user_agent,
            client_version: 'client-snapshot-download',
            scope: ['all'],
            token: token,
            token_str: token.token,
            token_lifetime: :permanent,
            label: 'Client snapshot download integration'
          )
          token.update!(owner: session)

          puts JSON.dump(token: token.token)
        RUBY
      end

      def write_download_mounter_token_file(services, token)
        services.succeeds(
          "install -d -m 0700 /private && " \
            "sh -c #{Shellwords.escape("umask 077 && printf '%s\\n' #{Shellwords.escape(token)} > /private/vpsadmin-api.token")}",
          timeout: 30
        )
      end

      def pool_download_path(pool_fs)
        "/#{pool_fs}/vpsadmin/download"
      end

      def export_download_dir(node, pool_fs:, pool_id:, services_address:)
        path = pool_download_path(pool_fs)
        escaped_export = Shellwords.escape("#{services_address}:#{path}")
        options = [
          'rw',
          'sync',
          'no_subtree_check',
          'no_root_squash',
          'insecure',
          "fsid=#{Integer(pool_id)}"
        ].join(',')

        node.wait_for_service('nfsd')
        node.succeeds("test -f #{Shellwords.escape(File.join(path, download_healthcheck_file))}", timeout: 30)
        node.execute("exportfs -u #{escaped_export}", timeout: 30)
        node.succeeds(
          "exportfs -i -o #{Shellwords.escape(options)} #{escaped_export}",
          timeout: 60
        )
        node.succeeds("exportfs -v | grep #{Shellwords.escape(path)}", timeout: 30)
      end

      def download_mount_dir(pool_id)
        File.join('/mnt/download', download_node_fqdn, pool_id.to_s)
      end

      def run_download_mounter(services)
        cmd = 'systemctl reset-failed vpsadmin-download-mounter.service; ' \
              'systemctl start vpsadmin-download-mounter.service'
        status, output = services.execute(cmd, timeout: 180)

        return [status, output] if status == 0

        _, diagnostics = services.execute(
          'systemctl status --no-pager vpsadmin-download-mounter.service || true; ' \
            'journalctl --no-pager -n 200 -u vpsadmin-download-mounter.service || true',
          timeout: 60
        )

        raise "Expected vpsadmin-download-mounter to start, got status #{status}. " \
              "Output:\n#{output}\nDiagnostics:\n#{diagnostics}"
      end

      def download_healthcheck_url(pool_id)
        "http://download.vpsadmin.test/#{download_node_fqdn}/#{pool_id}/#{download_healthcheck_file}"
      end

      def curl_download_healthcheck(services, pool_id)
        _, output = services.succeeds(
          "curl --silent --fail-with-body --max-time 30 " \
            "#{Shellwords.escape(download_healthcheck_url(pool_id))}",
          timeout: 60
        )

        output
      end

      def expect_download_mount_healthy(services, pool_id)
        mount_dir = download_mount_dir(pool_id)

        wait_until_block_succeeds(name: "download mount #{mount_dir}", timeout: 120) do
          services.succeeds("mountpoint #{Shellwords.escape(mount_dir)}", timeout: 30)
          curl_download_healthcheck(services, pool_id).strip == pool_id.to_s
        end
      end

      def vpsadminctl_snapshot_download(services, snapshot_id:, output_path:, resume: false)
        args = [
          'vpsadminctl',
          'snapshot',
          'download',
          snapshot_id.to_s,
          '--',
          '--quiet',
          '--no-delete-after',
          '--output',
          output_path
        ]
        args << '--resume' if resume

        services.succeeds(Shellwords.join(args), timeout: 600)
      end

      def file_sha256(machine, path)
        _, output = machine.succeeds(
          "sha256sum #{Shellwords.escape(path)}",
          timeout: 60
        )

        output.split.first
      end

      def ensure_snapshot_download_readable(services, node, pool_id:, pool_fs:, secret_key:, file_name:, url:)
        node_secret_dir = download_secret_dir_path(pool_fs: pool_fs, secret_key: secret_key)
        node_file_path = download_file_path(
          pool_fs: pool_fs,
          secret_key: secret_key,
          file_name: file_name
        )

        node.succeeds(
          "chmod 0755 #{Shellwords.escape(node_secret_dir)} && " \
            "chmod 0644 #{Shellwords.escape(node_file_path)}",
          timeout: 60
        )

        services.succeeds("umount -f #{Shellwords.escape(download_mount_dir(pool_id))}", timeout: 60)
        export_download_dir(
          node,
          pool_fs: pool_fs,
          pool_id: pool_id,
          services_address: download_services_address
        )
        run_download_mounter(services)
        expect_download_mount_healthy(services, pool_id)

        mounted_file_path = File.join(download_mount_dir(pool_id), secret_key, file_name)

        services.succeeds(
          "test -r #{Shellwords.escape(mounted_file_path)} && " \
            "curl --silent --fail-with-body --max-time 30 --range 0-0 " \
            "--output /dev/null #{Shellwords.escape(url)}",
          timeout: 60
        )
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        prepare_node_queues(node)
        services.unlock_transaction_signing_key(passphrase: 'test')
        ensure_snapshot_download_base_url(
          services,
          base_url: 'http://download.vpsadmin.test'
        )

        token = create_download_mounter_token(
          services,
          admin_user_id: admin_user_id
        ).fetch('token')
        write_download_mounter_token_file(services, token)
      end

      describe 'snapshot download client', order: :defined do
        it 'downloads a prepared archive and can resume an interrupted file' do
          setup = create_primary_dataset(
            services,
            primary_node: node,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'client-snapshot-download',
            primary_pool_fs: primary_pool_fs
          )
          pool_id = setup.fetch('primary_pool_id')

          export_download_dir(
            node,
            pool_fs: primary_pool_fs,
            pool_id: pool_id,
            services_address: download_services_address
          )
          run_download_mounter(services)
          expect_download_mount_healthy(services, pool_id)

          write_dataset_text(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/sentinel.txt',
            content: "client snapshot download sentinel\n"
          )
          write_dataset_payload(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/random.bin',
            mib: 2
          )

          snapshot = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'client-download-s1'
          )
          response = create_snapshot_download(
            services,
            snapshot_id: snapshot.fetch('id'),
            format: 'archive',
            send_mail: false
          )

          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          row = wait_for_snapshot_download_ready(services, response.fetch('id'))
          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect

          ensure_snapshot_download_readable(
            services,
            node,
            pool_id: pool_id,
            pool_fs: primary_pool_fs,
            secret_key: row.fetch('secret_key'),
            file_name: row.fetch('file_name'),
            url: row.fetch('url')
          )

          download_path = '/tmp/client-snapshot-download.tar.gz'
          resume_path = '/tmp/client-snapshot-download-resume.tar.gz'
          services.succeeds("rm -f #{Shellwords.escape(download_path)} #{Shellwords.escape(resume_path)}")

          vpsadminctl_snapshot_download(
            services,
            snapshot_id: snapshot.fetch('id'),
            output_path: download_path
          )

          listing = gzip_stream_listing(services, download_path)
          expect(listing.join("\n")).to include(
            'payload/sentinel.txt',
            'payload/random.bin'
          )
          expect(file_sha256(services, download_path)).to eq(row.fetch('sha256sum'))

          partial_size = [[Integer(row.fetch('size')) / 3, 1024].max, Integer(row.fetch('size')) - 1].min
          expect(partial_size).to be > 0
          services.succeeds(
            "head -c #{partial_size} #{Shellwords.escape(download_path)} > #{Shellwords.escape(resume_path)}",
            timeout: 60
          )

          vpsadminctl_snapshot_download(
            services,
            snapshot_id: snapshot.fetch('id'),
            output_path: resume_path,
            resume: true
          )

          expect(file_sha256(services, resume_path)).to eq(row.fetch('sha256sum'))
        end
      end
    '';
  }
)
