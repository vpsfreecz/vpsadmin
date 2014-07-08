class Task
  def self.query_params(task)
    "SELECT * FROM #{task['table_name']} WHERE id = #{task['id']}"
  end

  def initialize(db, params)
    @db = db

    params.each do |k, v|
      instance_variable_set(:"@#{k}", v)
    end
  end

  def execute

  end
end

require 'lib/tasks/dataset_action'
