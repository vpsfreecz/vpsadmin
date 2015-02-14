class VpsAdmin::API::Resources::DatasetPlan < HaveAPI::Resource
  version 1
  model ::DatasetPlan
  desc 'See dataset plans'

  params(:id) do
    integer :id, label: 'ID'
  end

  params(:common) do
    string :label
    string :description
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List dataset plans'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow
    end

    def exec
      ::DatasetPlan.all.limit(input[:limit]).offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show dataset plan'

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def exec
      ::DatasetPlan.find(params[:dataset_plan_id])
    end
  end
end
