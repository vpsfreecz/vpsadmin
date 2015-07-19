module Transactions::IntegrityCheck
  module Utils
    def serialize_query(q, parent, method)
      ret = []
            
      q.each do |obj|
        integrity_obj = register_object!(obj, parent)
        tmp = send(method, obj, integrity_obj)
        tmp[:integrity_object_id] = integrity_obj.id
        tmp[:ancestry] = integrity_obj.ancestry
        ret << tmp
      end

      ret
    end

    def register_object!(obj, parent = nil)
      ::IntegrityObject.create!(
          integrity_check: @integrity_check,
          class_name: obj.class.name,
          row_id: obj.id,
          parent: parent
      )
    end
  end
end
