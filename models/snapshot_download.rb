class SnapshotDownload < ActiveRecord::Base
  belongs_to :snapshot
  belongs_to :pool

  include Confirmable
end
