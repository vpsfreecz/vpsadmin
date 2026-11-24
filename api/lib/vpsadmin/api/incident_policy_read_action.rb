module VpsAdmin::API::IncidentPolicyReadAction
  def self.included(action)
    action.http_method :get
    action.route ''
    action.input do
      integer :offset, default: 0, fill: true, number: { min: 0 }, label: 'Rows to skip'
      integer :limit, default: 25, fill: true, number: { min: 1, max: 100 }, label: 'Rows per page'
      datetime :as_of, label: 'Counting cutoff', desc: 'Whole-second counting cutoff within the past 24 hours. Settings, ownership and action outcomes reflect the latest read.'
    end
    action.meta(:global) do
      output do
        integer :total_count, label: 'Total matching rows'
        integer :offset, label: 'Rows to skip'
        integer :limit, label: 'Rows per page'
        integer :next_offset, nullable: true, label: 'Next offset'
        datetime :as_of, label: 'Counting cutoff', desc: 'Whole-second counting cutoff within the past 24 hours. Settings, ownership and action outcomes reflect the latest read.'
        datetime :read_at, label: 'Current facts read at', desc: 'Time when this request read the current settings and outcomes.'
      end
    end
    action.authorize { |user| allow if user.role == :admin }
  end

  def read_projection
    @read_projection ||= ::IncidentPolicyReadProjection.new(as_of: input[:as_of], language: ::I18n.locale)
  end

  def projected(collection, **)
    result = read_projection.public_send(collection, **input.except(:as_of).compact, **)
    set_meta(result[:meta])
    result[:rows]
  rescue ArgumentError => e
    error!(e.message)
  end
end
