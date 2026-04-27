import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test-1-node.nix;
    common = import ../storage/remote-common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = seed.nodes.node.id;
      node2Id = seed.nodes.node.id;
      manageCluster = false;
    };
  in
  {
    name = "pool-create";
    description = ''
      Create a storage pool through the API and verify the node-side runtime
      datasets, healthcheck file, and persisted dataset properties.
    '';

    machines = import ../../../machines/v4/cluster/1-node.nix args;
    tags = [
      "ci"
      "vpsadmin"
      "pool"
    ];

    testScript = common + ''
      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
      end

      describe 'pool create' do
        it 'creates runtime datasets and pool metadata on the node' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'infra-primary',
            filesystem: 'tank/infra-primary',
            role: 'primary',
            properties: {
              refquota: 20_480,
              compression: false
            }
          )

          pool_id = pool.fetch('id')
          wait_for_pool_online(services, pool_id)
          expect(pool_id_by_filesystem(services, 'tank/infra-primary')).to eq(pool_id)

          expect(node.zfs_exists?('tank/infra-primary', type: 'filesystem', timeout: 30)).to be(true)
          expect(node.zfs_exists?('tank/infra-primary/vpsadmin', type: 'filesystem', timeout: 30)).to be(true)
          expect(node.zfs_exists?('tank/infra-primary/vpsadmin/config', type: 'filesystem', timeout: 30)).to be(true)
          expect(node.zfs_exists?('tank/infra-primary/vpsadmin/download', type: 'filesystem', timeout: 30)).to be(true)
          expect(node.zfs_exists?('tank/infra-primary/vpsadmin/mount', type: 'filesystem', timeout: 30)).to be(true)
          node.succeeds('test -d /tank/infra-primary/vpsadmin/config/vps')

          _, health = node.succeeds('cat /tank/infra-primary/vpsadmin/download/_vpsadmin-download-healthcheck')
          expect(health.strip).to eq(pool_id.to_s)

          properties = pool_dataset_properties(services, pool_id).to_h do |row|
            [row.fetch('name'), row]
          end

          expect(properties.fetch('refquota').fetch('value')).to eq(20_480)
          expect(properties.fetch('compression').fetch('value')).to be(false)
          expect(properties.fetch('sync').fetch('value')).to eq('standard')
          expect(properties.fetch('atime').fetch('value')).to be(false)
          expect(properties.values.map { |row| row.fetch('confirmed') }.uniq).to eq(['confirmed'])
          expect(properties.values.map { |row| row.fetch('inherited') }.uniq).to eq([false])
        end
      end
    '';
  }
)
