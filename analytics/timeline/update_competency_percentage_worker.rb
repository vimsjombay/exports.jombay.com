class UpdateCompletionPercentageService
  attr_accessor :options
  def call(options)
    @options = options
    update_completion_percentage()
  end

  def query_options
    query = {company_id: options[:company_id]}
    if(options[:journey_id])
      query[:id] = options[:journey_id]
    end
    query
  end

  def update_completion_percentage()
    Timeline::Journey.where(query).pluck(:id).each do |journey_id|
      journey = Timeline::Journey.find journey_id
      puts "Journey: #{journey.name}"
      journey.user_journies.each do |user_journey|
        puts user_journey.user_profile_document['user_document']['name']
        user_journey.send :update_stats_for_competencies
      end
    end
  end
end

# options = { company_id: '5d53bc0f227e5cc80a7048e8', journey_id: '66e26f8c6af54b001b65bc60'}
options = { company_id: '67e0e837cbd978388cd424a0'}
UpdateCompletionPercentageService.new.call(options)
