class RepeatableTask < ActiveRecord::Base
  def self.find_for(obj)
    self.find_by(
        class_name: obj.class.to_s.demodulize,
        table_name: obj.class.table_name,
        row_id: obj.id,
    )
  end

  def self.find_for!(obj)
    ret = find_for(obj)
    raise ::ActiveRecord::RecordNotFound unless ret
    ret
  end
end
