require 'io/console'

module VpsAdmin
  module StorageReconciler
    # Interactive Supervisor-side coordinator. No repair or approval entry point.
    class Capture
      class Incomplete < StandardError; end

      SCAN_SECONDS = 2 * 60 * 60

      attr_reader :run

      def initialize(pool_id:, mode:, private_dir:)
        @pool_id = Integer(pool_id)
        @mode = mode
        @private_dir = private_dir
        raise ArgumentError, 'unsupported capture mode' unless %w[bootstrap steady].include?(mode)
      end

      def run!
        unlock_signer! unless VpsAdmin::API::TransactionSigner.unlocked?
        config = broker_config!
        pool = Pool.includes(node: :location).find(@pool_id)
        scope = StorageIntegrityScope.find_or_create_by!(scope_key: "pool:#{pool.id}") do |row|
          row.pool = pool
          row.pool_catalog_id = pool.id
          row.mutation_epoch = 0
          row.state = :unverified
        end
        @run = StorageObservationRun.create!(
          storage_integrity_scope: scope, collector_version: Format::VERSION,
          mutation_epoch: scope.mutation_epoch, state: :collecting
        )
        store = PrivateStore.new(root: @private_dir, run_id: run.id, create: true)
        db = DbCapture.new(pool_id: pool.id, store:).capture!
        raise Incomplete, 'pool scope changed during database capture' unless
          db.fetch('scope_epoch').to_s == run.mutation_epoch.to_s

        catalog = db.fetch('pool')
        raise Incomplete, 'selected Pool identity changed before inventory' unless
          catalog.fetch('node_id').to_s == pool.node_id.to_s &&
          catalog.fetch('filesystem') == pool.filesystem

        run_uuid = SecureRandom.uuid
        attempt_uuid = SecureRandom.uuid
        nonce = SecureRandom.hex(32)
        deadline = Time.now.utc + SCAN_SECONDS
        zpool = catalog.fetch('filesystem').split('/').first
        transport = NodeTransport.new(
          node_domain: pool.node.domain_name, run_uuid:, attempt_uuid:,
          node_id: pool.node_id, pool_id: pool.id, zpool:,
          managed_root: catalog.fetch('filesystem'),
          roots: db.fetch('managed_roots'), nonce:, store:, config:
        )
        begin
          # Queue declare, bind and manual consumer start are the ACL preflight.
          transport.open!
          request = {
            protocol_version: Format::PROTOCOL_VERSION,
            run_uuid:, attempt_uuid:, node_id: pool.node_id, pool_id: pool.id,
            zpool:, zpool_guid: catalog['zpool_guid'],
            managed_root: catalog.fetch('filesystem'), roots: db.fetch('managed_roots'),
            routing_key: transport.routing_key, nonce:, deadline: deadline.iso8601(6)
          }
          chain, = TransactionChains::Storage::Inventory.fire(request)
          transaction = chain.transactions.sole
          raise Incomplete, 'inventory command was not signed' if transaction.signature.to_s.empty?

          final, final_delivery = transport.receive_until_final!(
            deadline:, failure_check: lambda {
              Timeout.timeout(5) do
                transaction.reload
                chain.reload
              end
              chain.failed? || chain.fatal? ||
                (transaction.done == 'done' && transaction.status.to_i != 1)
            }
          )
          result = wait_for_result!(transaction, deadline:)
          validate_result!(result, final)
          raise Incomplete, 'observed zpool GUID differs from catalog' if
            catalog['zpool_guid'] && catalog['zpool_guid'].to_s != final.fetch('first').fetch('zpool_guid')

          stale = db.fetch('known_chain_overlap') ||
                  scope.reload.mutation_epoch.to_s != run.mutation_epoch.to_s ||
                  StorageFreezeControl.singleton!.epoch.to_s != db.fetch('freeze_epoch').to_s
          transport.seal!
          manifest = manifest_for(
            store:, db:, final:, run_uuid:, attempt_uuid:, pool:,
            state: stale ? 'stale' : 'complete'
          )
          # The sealed pre-ACK manifest is private and not accepted by offline readers.
          seal = manifest.merge('state' => 'sealed_pending_ack')
          seal['digest'] = Format.digest(seal.except('digest'))
          store.write('capture-seal.json') { |file| file.write("#{Format.canonical(seal)}\n") }
          transport.ack_final!(final_delivery)
          run.update!(
            state: stale ? :stale : :complete,
            db_observed_from_at: Time.iso8601(db.fetch('observed_from_at')),
            db_observed_until_at: Time.iso8601(db.fetch('observed_until_at')),
            node_observed_from_at: Time.iso8601(final.fetch('first').fetch('observed_from_at')),
            node_observed_until_at: Time.iso8601(final.fetch('second').fetch('observed_until_at')),
            counts_json: Format.canonical({ db: db.fetch('row_count'), zfs: final.fetch('row_count') }),
            digest: manifest.fetch('digest')
          )
          store.write('manifest.json') { |file| file.write("#{Format.canonical(manifest)}\n") }
          stale ? 2 : 0
        ensure
          transport.close
        end
      rescue StandardError => e
        mark_incomplete!(e)
        raise
      end

      def unlock_signer!
        tty = IO.console
        raise Incomplete, 'capture requires a controlling TTY' unless tty&.tty?

        tty.print('Transaction-key passphrase: ')
        passphrase = tty.noecho(&:gets)
        tty.puts
        raise Incomplete, 'transaction-key passphrase was not supplied' unless passphrase

        begin
          VpsAdmin::API::TransactionSigner.unlock(passphrase.chomp)
          signature = VpsAdmin::API::TransactionSigner.sign_base64('storage inventory preflight')
          raise Incomplete, 'transaction signer is unavailable' if signature.to_s.empty?
        ensure
          passphrase.replace("\0" * passphrase.bytesize)
        end
      end

      private

      def broker_config!
        config = VpsAdmin::Supervisor::Cli.parse_config
        {
          'hosts' => config.fetch('hosts'), 'vhost' => config.fetch('vhost', '/'),
          'username' => config.fetch('username'), 'password' => config.fetch('password')
        }
      rescue StandardError
        raise Incomplete, 'Supervisor broker configuration is unavailable'
      end

      def wait_for_result!(transaction, deadline:)
        loop do
          raise Incomplete, 'signed inventory result timed out' if Time.now.utc >= deadline

          Timeout.timeout([deadline - Time.now.utc, 10].min) { transaction.reload }
          if transaction.done == 'done'
            raise Incomplete, 'signed inventory transaction failed' unless transaction.status.to_i == 1

            output = JSON.parse(transaction.output.to_s).fetch('execute')
            raise Incomplete, 'signed inventory transaction failed' unless output.fetch('status') == 'ok'

            return output
          end
          sleep 2
        end
      rescue JSON::ParserError, KeyError, Timeout::Error
        raise Incomplete, 'signed inventory result is unavailable'
      end

      def validate_result!(result, final)
        first = final.fetch('first')
        raise Incomplete, 'signed inventory result does not match final marker' unless
          result.fetch('inventory_version') == Format::PROTOCOL_VERSION &&
          result.fetch('object_count') == first.fetch('count') &&
          result.fetch('inventory_digest') == first.fetch('digest') &&
          result.fetch('chunk_chain') == final.fetch('chunk_chain')
      rescue KeyError
        raise Incomplete, 'signed inventory result is incomplete'
      end

      def manifest_for(store:, db:, final:, run_uuid:, attempt_uuid:, pool:, state:)
        data = {
          'version' => Format::VERSION,
          'policy_version' => Format::LEGACY_POLICY_VERSION,
          'run_id' => run.id.to_s, 'run_uuid' => run_uuid,
          'attempt_uuid' => attempt_uuid, 'mode' => @mode, 'state' => state,
          'confidence' => 'advisory_unguarded', 'finding_key' => store.key_metadata,
          'scope' => {
            'node_id' => pool.node_id.to_s, 'pool_id' => pool.id.to_s,
            'zpool' => db.fetch('pool').fetch('filesystem').split('/').first,
            'managed_root' => db.fetch('pool').fetch('filesystem'),
            'mutation_epoch' => run.mutation_epoch.to_s,
            'freeze_epoch' => db.fetch('freeze_epoch').to_s
          },
          'db' => db, 'zfs' => {
            'row_count' => final.fetch('row_count'), 'digest' => final.fetch('first').fetch('digest'),
            'chunk_chain' => final.fetch('chunk_chain'),
            'first' => final.fetch('first'), 'second' => final.fetch('second')
          }
        }
        data['digest'] = Format.digest(data)
        data
      end

      def mark_incomplete!(error)
        return unless run&.persisted?

        run.update_columns(state: StorageObservationRun.states.fetch('incomplete'),
                           failure_code: error.class.name.split('::').last,
                           updated_at: Time.current)
      rescue StandardError
        nil
      end
    end
  end
end
