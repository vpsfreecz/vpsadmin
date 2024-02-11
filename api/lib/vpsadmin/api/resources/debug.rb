require 'objspace'

module VpsAdmin::API::Resources
  class Debug < HaveAPI::Resource
    desc 'Internal debug actions'

    class ListObjectCounts < HaveAPI::Action
      desc 'List Ruby objects and their counts'

      output(:hash_list) do
        string :object
        integer :count
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ObjectSpace.each_object.each_with_object(Hash.new(0)) do |obj, hash|
          hash[obj.class] += 1
        end.sort_by do |_klass, count|
          -count
        end.map do |klass, count|
          { object: klass, count: count }
        end
      end
    end

    class HashTop < HaveAPI::Action
      desc 'List largest Ruby hashes'

      input(:hash) do
        integer :limit, default: 10, fill: true
      end

      output(:hash_list) do
        integer :size
        custom :sample
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        hashes = []

        ObjectSpace.each_object do |obj|
          next unless obj.is_a?(::Hash)

          sample = {}

          obj.each_key.with_index do |k, i|
            sample[k] = obj[k].inspect[0..40]
            break if i >= 4
          end

          hashes << {
            size: obj.size,
            sample: sample
          }
        end

        hashes.sort do |a, b|
          b[:size] <=> a[:size]
        end[0..input[:limit]]
      end
    end

    class ArrayTop < HaveAPI::Action
      desc 'List largest Ruby arrays'

      input(:hash) do
        integer :limit, default: 10, fill: true
      end

      output(:hash_list) do
        integer :size
        custom :sample
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        arrays = []

        ObjectSpace.each_object do |obj|
          next if !obj.is_a?(::Array) || obj.equal?(arrays)

          sample = []

          obj.each_with_index do |v, i|
            sample << v.inspect[0..40]
            break if i >= 4
          end

          arrays << {
            size: obj.size,
            sample: sample
          }
        end

        arrays.sort do |a, b|
          b[:size] <=> a[:size]
        end[0..input[:limit]]
      end
    end
  end
end
