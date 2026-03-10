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
    Timeline::Journey.where(query_options).pluck(:id).each do |journey_id|
      journey = Timeline::Journey.find journey_id
      puts "Journey: #{journey.name}"
      journey.user_journies.set({
        participated_content_ids: [],
        completed_content_ids: [],
        participation_percentage: 0,
        completion_percentage: 0
      })
      journey.milestones.each do |milestone|
        leaderboard_date = milestone.leaderboard_lockdown_date || Time.now 
        milestone.user_milestones.each do |user_milestone|
          puts "Learner : #{user_milestone.user_profile_document['user_document']['name']}"
          completed_user_contents = user_milestone.user_contents.completed.where(
            'content_document.enable_for_completion': true,
            :'content_document.start_date'.lte => Time.now
          )
          completed_content_ids = completed_user_contents.pluck(:content_id)
          completed_content_ids_before_lockdown = completed_user_contents.where(:completed_at.lte => leaderboard_date).pluck(:content_id)

          participated_content_ids = user_milestone.content_ids_applicable_for_completion_rate

          user_milestone.set({
            participated_content_ids: participated_content_ids,
            completed_content_ids_before_lockdown: completed_content_ids_before_lockdown,
            completed_content_ids: completed_content_ids
          })

          if(completed_content_ids.size > 0 && journey.company_document['enable_milestone_leaderboard'])
            milestone.update_leaderboard_for(user_milestone.reload.id)
          else
            milestone.leaderboard.remove_member(user_milestone.id.to_s)
          end
          user_journey = Timeline::UserJourney.find user_milestone.user_journey_id

          participated_content_ids = user_journey.participated_content_ids | participated_content_ids
          completed_content_ids = user_journey.completed_content_ids | completed_content_ids

          user_journey.set(
            participated_content_ids: participated_content_ids,
            completed_content_ids: completed_content_ids,
            participation_percentage: user_journey.calc_participation_percentage,
            completion_percentage: user_journey.calc_completion_percentage
          )

          user_journey.send :update_stats_for_competencies
        end
      end
    end
  end
end

# options = { company_id: '5d53bc0f227e5cc80a7048e8', journey_id: '66e26f8c6af54b001b65bc60'}
options = { company_id: '67e0e837cbd978388cd424a0'}
UpdateCompletionPercentageService.new.call(options)
