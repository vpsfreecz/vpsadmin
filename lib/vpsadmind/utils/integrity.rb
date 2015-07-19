module VpsAdmind::Utils
  module Integrity
    def state_fact(db, object, name, value, real_value, severity = :normal, msg = nil)
      status = value == real_value

      severity_i = [:low, :normal, :high].index(severity)

      db.prepared(
          'INSERT INTO integrity_facts
            (integrity_object_id, name, value, status, severity, message,
            created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)',
          object.is_a?(Integer) ? object : object['integrity_object_id'],
          name,
          YAML.dump(value),
          status ? 1 : 0,
          severity_i,
          status ? nil : msg,
          Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      )
    end

    def create_integrity_object(db, check_id, parent, class_name)
      db.prepared(
          'INSERT INTO integrity_objects
            (integrity_check_id, class_name, ancestry, ancestry_depth,
             created_at)
          VALUES (?, ?, ?, ?, ?)',
          check_id, class_name,
          parent['ancestry'] || parent['integrity_object_id'].to_s,
          parent['ancestry'] ? parent['ancestry'].split('/').count : 1,
          Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      )
      db.insert_id
    end
  end
end
