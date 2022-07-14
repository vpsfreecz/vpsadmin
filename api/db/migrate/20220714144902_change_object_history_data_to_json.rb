class ChangeObjectHistoryDataToJson < ActiveRecord::Migration[6.1]
  class ObjectHistory < ActiveRecord::Base ; end

  def up
    ObjectHistory.all.each do |v|
      next if v.event_data.nil?
      v.update!(event_data: JSON.dump(YAML.load(v.event_data)))
    end
  end

  def down
    ObjectHistory.all.each do |v|
      next if v.event_data.nil?
      v.update!(event_data: YAML.dump(JSON.parse(v.event_data)))
    end
  end
end
