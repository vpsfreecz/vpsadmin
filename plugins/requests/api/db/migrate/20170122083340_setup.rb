class Setup < ActiveRecord::Migration
  def change
    create_table :user_requests do |t|
      t.references  :user,                null: true
      t.string      :type,                null: false, limit: 255
      t.integer     :state,               null: false, default: 0
      t.string      :api_ip_addr,         null: false, limit: 127
      t.string      :api_ip_ptr,          null: false
      t.string      :client_ip_addr,      null: true,  limit: 127
      t.string      :client_ip_ptr,       null: true
      t.integer     :last_mail_id,        null: false, default: 0
      t.references  :admin,               null: true
      t.string      :admin_response,      null: true,  limit: 500
      t.timestamps

      # Registration fields
      t.string      :login,               limit: 75
      t.string      :full_name,           limit: 255
      t.string      :org_name,            limit: 255
      t.string      :org_id,              limit: 30
      t.string      :email,               limit: 255
      t.text        :address,             limit: 500
      t.integer     :year_of_birth
      t.string      :how,                 limit: 500
      t.string      :note,                limit: 500
      t.references  :os_template
      t.references  :location
      t.string      :currency,            limit: 10
      t.references  :language

      # Change request fields
      # full_name
      # email
      # address
      t.string      :change_reason,       null: true,  limit: 255
    end

    add_index :user_requests, :user_id
    add_index :user_requests, :type
    add_index :user_requests, :state
    add_index :user_requests, :admin_id

    reversible do |dir|
      dir.up do
        next unless table_exists?(:members_changes)

        ActiveRecord::Base.connection.execute(
            "INSERT INTO user_requests (
              user_id,
              type,
              state,
              api_ip_addr,
              api_ip_ptr,
              last_mail_id,
              admin_id,
              admin_response,
              created_at,
              updated_at,

              login,
              full_name,
              email,
              address,
              year_of_birth,
              how,
              note,
              os_template_id,
              location_id,
              currency,
              language_id,

              change_reason
            )

            SELECT
              m_applicant,
              CASE m_type
              WHEN 'add' THEN 'RegistrationRequest'
              WHEN 'change' THEN 'ChangeRequest'
              END,
              CASE m_state
              WHEN 'awaiting' THEN 0
              WHEN 'approved' THEN 1
              WHEN 'denied' THEN 2
              WHEN 'invalid' THEN 2
              WHEN 'ignored' THEN 3
              END,
              m_addr,
              m_addr_reverse,
              m_last_mail_id,
              m_changed_by,
              m_admin_response,
              FROM_UNIXTIME(m_created),
              FROM_UNIXTIME(m_changed_at),

              m_nick,
              m_name,
              m_mail,
              m_address,
              m_year,
              m_how,
              m_note,
              m_distribution,
              m_location,
              m_currency,
              IFNULL((
                SELECT id
                FROM languages
                WHERE code COLLATE utf8_general_ci = m_language COLLATE utf8_general_ci
              ), 1),

              m_reason

            FROM members_changes
            ORDER BY m_id"
        )
      end
    end
  end
end
