module VpsAdmin
  module StorageReconciler
    # Complete-only private artifact reader and offline report writer.
    class Artifacts
      class Invalid < StandardError; end

      MAX_ROWS = 300_000

      attr_reader :manifest, :store

      def initialize(store)
        @store = store
        @manifest = store.read_json('manifest.json')
        raise Invalid, 'capture is not sealed complete' unless
          manifest['version'] == Format::VERSION && manifest['state'] == 'complete'
        raise Invalid, 'capture is not advisory' unless manifest['confidence'] == 'advisory_unguarded'
        raise Invalid, 'unsupported comparator policy' unless
          manifest['policy_version'] == Format::POLICY_VERSION
        raise Invalid, 'capture run ID mismatch' unless manifest['run_id'].to_s == store.run_id.to_s

        store.check_key_metadata!(manifest.fetch('finding_key'))
        raise Invalid, 'manifest digest mismatch' unless
          manifest['digest'] == Format.digest(manifest.except('digest'))
      rescue Errno::ENOENT
        raise Invalid, 'capture is not sealed complete'
      end

      def compare!
        _db, _zfs, findings, report = computed_comparison
        write_records("findings-v#{Format::POLICY_VERSION}.jsonl", findings)
        write_json("report-v#{Format::POLICY_VERSION}.json", report)
        report
      end

      def dry_run!
        db, zfs, findings, report = verified_comparison!
        planner = ProofPlanner.new(db_records: db, zfs_records: zfs,
                                   findings:, manifest:, report:, store:)
        planner.actions
        actions = findings.map do |finding|
          fields = finding.fetch('fields')
          key = Format.digest([Format::POLICY_VERSION, fields.fetch('finding_key'),
                               'no_action', fields.fetch('evidence_digest')])
          Format.record('candidate_action', {
            'action_key' => key, 'finding_key' => fields.fetch('finding_key'),
            'status' => 'advisory_unapproved', 'operation' => nil,
            'target_kind' => fields['subject_kind'], 'target_id' => fields['subject_id'],
            'before_image' => nil, 'after_image' => nil,
            'before_digest' => nil, 'after_digest' => nil,
            'proof_requirements' => fields.fetch('blockers'),
            'reason' => 'no repair is proved by this observer capture'
          })
        end
        write_records("candidate-actions-v#{Format::POLICY_VERSION}.jsonl", actions)
        summary = {
          'version' => Format::VERSION, 'run_id' => manifest.fetch('run_id'),
          'status' => 'advisory_unapproved', 'candidate_count' => actions.size,
          'executable_count' => 0, 'digest' => digest_records(actions),
          'report_digest' => report.fetch('digest')
        }
        write_json("dry-run-v#{Format::POLICY_VERSION}.json", summary)
        summary
      end

      def plan!
        db, zfs, findings, report = verified_comparison!
        actions = ProofPlanner.new(db_records: db, zfs_records: zfs,
                                   findings:, manifest:, report:, store:).actions
        write_records("candidate-actions-v#{Format::PLAN_POLICY_VERSION}.jsonl", actions)
        summary = {
          'version' => Format::VERSION,
          'plan_policy_version' => Format::PLAN_POLICY_VERSION,
          'run_id' => manifest.fetch('run_id'), 'mode' => manifest.fetch('mode'),
          'confidence' => manifest.fetch('confidence'),
          'key_id' => store.key_id,
          'capture_digest' => manifest.fetch('digest'),
          'report_digest' => report.fetch('digest'),
          'action_count' => actions.size, 'action_digest' => digest_records(actions),
          'disposition_counts' => actions.group_by { |row| row.dig('fields', 'disposition') }
                                         .transform_values(&:size),
          'finding_code_counts' => actions.group_by { |row| row.dig('fields', 'finding_code') }
                                          .transform_values(&:size),
          'executable_count' => 0
        }
        summary['digest'] = Format.digest(summary)
        write_json("dry-run-v#{Format::PLAN_POLICY_VERSION}.json", summary)
        summary
      end

      private

      def computed_comparison
        db = read_records('db.jsonl', 'db_object', manifest.fetch('db'))
        zfs = read_records('zfs.jsonl', 'zfs_object', manifest.fetch('zfs'))
        findings = Comparator.new(db_records: db, zfs_records: zfs,
                                  manifest:, store:).compare
        report = {
          'version' => Format::VERSION, 'policy_version' => Format::POLICY_VERSION,
          'run_id' => manifest.fetch('run_id'), 'mode' => manifest.fetch('mode'),
          'confidence' => 'advisory_unguarded',
          'historical_proof' => manifest.fetch('db').fetch('confirmation_coverage'),
          'findings' => findings.size,
          'finding_counts' => findings.group_by { |row| row.fetch('fields').fetch('code') }
                                      .transform_values(&:size),
          'finding_digest' => digest_records(findings),
          'capture_digest' => manifest.fetch('digest')
        }
        report['digest'] = Format.digest(report)
        [db, zfs, findings, report]
      end

      def verified_comparison!
        db, zfs, findings, expected_report = computed_comparison
        verify_existing_file!("findings-v#{Format::POLICY_VERSION}.jsonl",
                              row_count: findings.size, digest: digest_records(findings))
        verify_existing_file!("report-v#{Format::POLICY_VERSION}.json",
                              row_count: 1,
                              digest: Digest::SHA256.hexdigest("#{Format.canonical(expected_report)}\n"))
        report = store.read_json("report-v#{Format::POLICY_VERSION}.json")
        raise Invalid, 'report differs from recomputed comparison' unless report == expected_report

        [db, zfs, findings, report]
      end

      def read_records(name, kind, metadata)
        rows = []
        digest = Digest::SHA256.new
        store.each_line(name) do |line|
          raise Invalid, 'record limit exceeded' if rows.size >= MAX_ROWS

          rows << Format.parse_line!(line, expected_kind: kind)
          digest.update(line)
        end
        raise Invalid, 'artifact count or checksum differs from manifest' unless
          rows.size == metadata.fetch('row_count') && digest.hexdigest == metadata.fetch('digest')

        rows
      rescue Format::Invalid, KeyError
        raise Invalid, 'invalid or incomplete artifact'
      end

      def write_records(name, rows)
        publish_file(name, row_count: rows.size, digest: digest_records(rows)) do |file|
          rows.each { |row| file.write("#{Format.canonical(row)}\n") }
        end
      end

      def write_json(name, value)
        line = "#{Format.canonical(value)}\n"
        publish_file(name, row_count: 1, digest: Digest::SHA256.hexdigest(line)) do |file|
          file.write(line)
        end
      end

      def publish_file(name, row_count:, digest:, &)
        store.write(name, &)
      rescue PrivateStore::Invalid => e
        raise unless e.message == 'artifact already exists'

        verify_existing_file!(name, row_count:, digest:)
      rescue Errno::EEXIST
        # A concurrent invocation published the immutable file first.
        verify_existing_file!(name, row_count:, digest:)
      end

      def verify_existing_file!(name, row_count:, digest:)
        actual_digest = Digest::SHA256.new
        actual_count = 0
        store.each_line(name) do |line|
          actual_digest.update(line)
          actual_count += 1
        end
        return if actual_count == row_count && actual_digest.hexdigest == digest

        raise Invalid, 'existing report artifact differs from recomputed output'
      end

      def digest_records(rows)
        digest = Digest::SHA256.new
        rows.each { |row| digest.update("#{Format.canonical(row)}\n") }
        digest.hexdigest
      end
    end
  end
end
