module VpsAdmind
  class Commands::IntegrityCheck::Finalize < Commands::Base
    handle 6001

    def exec
      db = Db.new

      db.transaction do |t|
        time = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

        # Close integrity object
        t.prepared(
            'UPDATE integrity_objects o SET
               status = IF(
                 (SELECT COUNT(*) FROM integrity_facts f
                 WHERE f.integrity_object_id = o.id AND severity > 0) > 0,
                 2, 1
               ),
               checked_facts = (
                 SELECT COUNT(*)
                 FROM integrity_facts
                 WHERE integrity_object_id = o.id
               ),
               true_facts = (
                 SELECT COUNT(*)
                 FROM integrity_facts
                 WHERE integrity_object_id = o.id AND status = 1
               ),
               false_facts = (
                 SELECT COUNT(*)
                 FROM integrity_facts
                 WHERE integrity_object_id = o.id AND status = 0
               ),
               updated_at = ?
             WHERE integrity_check_id = ?',
             time, @integrity_check_id
        )

        # Close integrity check
        st = t.prepared_st(
            'SELECT COUNT(*)
             FROM integrity_facts f
             INNER JOIN integrity_objects o ON f.integrity_object_id = o.id
             WHERE o.integrity_check_id = ? AND f.status = 0 AND f.severity > 0',
             @integrity_check_id
        )
        failed = st.fetch[0]
        st.close

        t.prepared(
            'UPDATE integrity_checks SET
              status = ?,
              checked_objects = (
                SELECT COUNT(*) FROM integrity_objects
                WHERE integrity_check_id = ?
              ),
              integral_objects = (
                SELECT COUNT(*)
                FROM integrity_objects f
                WHERE integrity_check_id = ? AND status = 1
              ),
              broken_objects = (
                SELECT COUNT(*)
                FROM integrity_objects f
                WHERE integrity_check_id = ? AND status = 2
              ),
              checked_facts = (
                SELECT COUNT(*)
                FROM integrity_facts f
                INNER JOIN integrity_objects o ON f.integrity_object_id = o.id
                WHERE o.integrity_check_id = ?
              ),
              true_facts = (
                SELECT COUNT(*)
                FROM integrity_facts f
                INNER JOIN integrity_objects o ON f.integrity_object_id = o.id
                WHERE o.integrity_check_id = ? AND f.status = 1
              ),
              false_facts = (
                SELECT COUNT(*)
                FROM integrity_facts f
                INNER JOIN integrity_objects o ON f.integrity_object_id = o.id
                WHERE o.integrity_check_id = ? AND f.status = 0
              ),
              updated_at = ?,
              finished_at = ?
            WHERE id = ?
            ',
            failed > 0 ? 2 : 1,
            @integrity_check_id, @integrity_check_id, @integrity_check_id,
            @integrity_check_id, @integrity_check_id, @integrity_check_id,
            time, time, @integrity_check_id
        )
      end

      db.close
      ok
    end

    def rollback
      ok
    end
  end
end
