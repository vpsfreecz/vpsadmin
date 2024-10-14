module VpsAdmin::API
  module Operations::Dataset::Utils
    def check_refquota(dip, path, refquota)
      # Refquota enforcement
      return unless dip.pool.refquota_check
      raise VpsAdmin::API::Exceptions::PropertyInvalid, 'refquota must be set' if refquota.nil?

      i = 0
      path.each do |p|
        i += 1 if p.new_record?

        if i > 1
          raise VpsAdmin::API::Exceptions::DatasetNestingForbidden,
                'Cannot create more than one dataset at a time'
        end
      end
    end
  end
end
