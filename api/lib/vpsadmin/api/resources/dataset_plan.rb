class VpsAdmin::API::Resources::DatasetPlan < HaveAPI::Resource
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

    authorize do |_u|
      allow
    end

    def exec
      with_pagination(::DatasetPlan.all)
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show dataset plan'

    output do
      use :all
    end

    authorize do |_u|
      allow
    end

    def exec
      ::DatasetPlan.find(params[:dataset_plan_id])
    end
  end
end
