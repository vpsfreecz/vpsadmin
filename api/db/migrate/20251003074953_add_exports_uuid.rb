require 'securerandom'

class AddExportsUuid < ActiveRecord::Migration[7.2]
  class Export < ActiveRecord::Base; end

  class Uuid < ActiveRecord::Base
    belongs_to :owner, polymorphic: true
  end

  def change
    add_column :exports, :uuid_id, :bigint, null: true
    add_index :exports, :uuid_id, unique: true

    reversible do |dir|
      dir.up do
        ::Export.all.each do |export|
          uuid = nil

          10.times do
            uuid = ::Uuid.create!(uuid: SecureRandom.uuid)
          rescue ActiveRecord::RecordNotUnique
            sleep(0.1)
            next
          else
            break
          end

          raise 'Unable to generate uuid' if uuid.nil?

          export.update!(uuid_id: uuid.id)
          uuid.update!(owner: export)
        end
      end

      dir.down do
        ::Export.all.each do |export|
          export.uuid.destroy!
        end
      end
    end

    change_column_null :exports, :uuid_id, false
  end
end
