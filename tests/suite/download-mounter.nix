import ../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    servicesAddress = "192.168.10.10";
    nodeFqdn = "${nodeSeed.domain}.${seed.environment.domain}";
    common = import ./storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
    machines = import ../machines/cluster/1-node.nix (
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
    name = "download-mounter";

    description = ''
      Mount pool download directories through vpsadmin-download-mounter and
      verify HTTP file serving, healthchecks, and remount recovery.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
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
          user_agent = UserAgent.find_or_create!('download-mounter-integration')
          session = UserSession.create!(
            user: admin,
            admin: admin,
            auth_type: 'token',
            api_ip_addr: '127.0.0.1',
            client_ip_addr: '127.0.0.1',
            user_agent: user_agent,
            client_version: 'download-mounter-integration',
            scope: ['all'],
            token: token,
            token_str: token.token,
            token_lifetime: :permanent,
            label: 'Download mounter integration'
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

      def unexport_download_dir(node, pool_fs:, services_address:)
        path = pool_download_path(pool_fs)
        node.succeeds(
          "exportfs -u #{Shellwords.escape("#{services_address}:#{path}")}",
          timeout: 60
        )
      end

      def download_mount_dir(pool_id)
        File.join('/mnt/download', download_node_fqdn, pool_id.to_s)
      end

      def run_download_mounter(services, expect_success: true)
        cmd = 'systemctl reset-failed vpsadmin-download-mounter.service; ' \
              'systemctl start vpsadmin-download-mounter.service'
        status, output = services.execute(cmd, timeout: 180)
        succeeded = status == 0

        return [status, output] if succeeded == expect_success

        _, diagnostics = services.execute(
          'systemctl status --no-pager vpsadmin-download-mounter.service || true; ' \
            'journalctl --no-pager -n 200 -u vpsadmin-download-mounter.service || true',
          timeout: 60
        )
        expectation = expect_success ? 'succeed' : 'fail'

        raise "Expected vpsadmin-download-mounter to #{expectation}, " \
              "got status #{status}. Output:\n#{output}\nDiagnostics:\n#{diagnostics}"
      end

      def download_healthcheck_url(pool_id)
        "http://download.vpsadmin.test/#{download_node_fqdn}/#{pool_id}/#{download_healthcheck_file}"
      end

      def download_file_url(pool_id, relative_path)
        clean_path = relative_path.sub(%r{\A/+}, "")

        "http://download.vpsadmin.test/#{download_node_fqdn}/#{pool_id}/#{clean_path}"
      end

      def curl_download_healthcheck(services, pool_id)
        _, output = services.succeeds(
          "curl --silent --fail-with-body --max-time 30 " \
            "#{Shellwords.escape(download_healthcheck_url(pool_id))}",
          timeout: 60
        )

        output
      end

      def curl_download_file(services, pool_id, relative_path)
        _, output = services.succeeds(
          "curl --silent --fail-with-body --max-time 30 " \
            "#{Shellwords.escape(download_file_url(pool_id, relative_path))}",
          timeout: 60
        )

        output
      end

      def write_pool_download_text(node, pool_fs:, relative_path:, content:)
        full_path = File.join(pool_download_path(pool_fs), relative_path)

        node.succeeds("mkdir -p #{Shellwords.escape(File.dirname(full_path))}", timeout: 60)
        node.succeeds("cat > #{Shellwords.escape(full_path)} <<'EOF'\n#{content}EOF", timeout: 60)
        content
      end

      def expect_download_mount_healthy(services, pool_id)
        mount_dir = download_mount_dir(pool_id)

        wait_until_block_succeeds(name: "download mount #{mount_dir}", timeout: 120) do
          services.succeeds("mountpoint #{Shellwords.escape(mount_dir)}", timeout: 30)
          curl_download_healthcheck(services, pool_id).strip == pool_id.to_s
        end
      end

      def replace_with_bad_mount(services, mount_dir)
        bad_dir = '/tmp/download-mounter-bad'

        services.succeeds("umount -f #{Shellwords.escape(mount_dir)}", timeout: 60)
        services.succeeds(
          "rm -rf #{Shellwords.escape(bad_dir)} && " \
            "mkdir -p #{Shellwords.escape(bad_dir)} && " \
            "printf 'wrong-pool\\n' > #{Shellwords.escape(File.join(bad_dir, download_healthcheck_file))} && " \
            "mount --bind #{Shellwords.escape(bad_dir)} #{Shellwords.escape(mount_dir)}",
          timeout: 60
        )
        services.succeeds("mountpoint #{Shellwords.escape(mount_dir)}", timeout: 30)
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        prepare_node_queues(node)
        services.unlock_transaction_signing_key(passphrase: 'test')

        token = create_download_mounter_token(
          services,
          admin_user_id: admin_user_id
        ).fetch('token')
        write_download_mounter_token_file(services, token)
      end

      describe 'download mounter', order: :defined do
        it 'mounts the pool download directory and serves the healthcheck' do
          @setup = create_primary_dataset(
            services,
            primary_node: node,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'download-mounter',
            primary_pool_fs: primary_pool_fs
          )
          @pool_id = @setup.fetch('primary_pool_id')

          export_download_dir(
            node,
            pool_fs: primary_pool_fs,
            pool_id: @pool_id,
            services_address: download_services_address
          )

          run_download_mounter(services)

          expect_download_mount_healthy(services, @pool_id)
          expect(curl_download_healthcheck(services, @pool_id).strip).to eq(@pool_id.to_s)
        end

        it 'serves a file from the pool download directory through the mounted frontend' do
          write_pool_download_text(
            node,
            pool_fs: primary_pool_fs,
            relative_path: 'manual/download-mounter.txt',
            content: "download mounter sentinel\n"
          )

          expect(curl_download_file(services, @pool_id, 'manual/download-mounter.txt')).to eq(
            "download mounter sentinel\n"
          )
        end

        it 'remounts when the directory has been unmounted' do
          mount_dir = download_mount_dir(@pool_id)

          services.succeeds("umount -f #{Shellwords.escape(mount_dir)}", timeout: 60)
          export_download_dir(
            node,
            pool_fs: primary_pool_fs,
            pool_id: @pool_id,
            services_address: download_services_address
          )

          run_download_mounter(services)

          expect_download_mount_healthy(services, @pool_id)
        end

        it 'remounts a broken NFS mount after the export returns' do
          unexport_download_dir(
            node,
            pool_fs: primary_pool_fs,
            services_address: download_services_address
          )

          run_download_mounter(services, expect_success: false)

          export_download_dir(
            node,
            pool_fs: primary_pool_fs,
            pool_id: @pool_id,
            services_address: download_services_address
          )
          run_download_mounter(services)

          expect_download_mount_healthy(services, @pool_id)
        end

        it 'remounts a stale mounted directory with the wrong healthcheck' do
          mount_dir = download_mount_dir(@pool_id)

          replace_with_bad_mount(services, mount_dir)
          export_download_dir(
            node,
            pool_fs: primary_pool_fs,
            pool_id: @pool_id,
            services_address: download_services_address
          )
          expect(curl_download_healthcheck(services, @pool_id).strip).to eq('wrong-pool')

          run_download_mounter(services)

          expect_download_mount_healthy(services, @pool_id)
        end

        it 'is idempotent with a healthy mount' do
          run_download_mounter(services)

          expect_download_mount_healthy(services, @pool_id)
        end
      end
    '';
  }
)
