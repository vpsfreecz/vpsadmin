module VpsAdmin::API::Tasks
  class Lifetimes < Base
    def progress
      VpsAdmin::API::Lifetimes.models.each do |m|
        puts "Model #{m}"

        m.where('expiration_date < NOW()').each do |obj|
          obj.progress_object_state(reason: 'Expiration date has passed.')
        end
      end
    end
  end
end
