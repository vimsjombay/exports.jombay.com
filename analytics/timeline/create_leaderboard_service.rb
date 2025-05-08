module Timeline
  class CreateLeaderboardService
    attr_accessor :options
    def initialize(inputs)
      @options = inputs
    end

    def create_leaderboard
      Timeline::Journey.where(company_id: options[:company_id]).each do |journey|
        puts "Journey: #{journey.id}"
        journey.milestones.each do |milestone|
          milestone.user_milestones.each do |user_milestone|
            archived_content_ids = user_milestone.user_contents.archived.pluck(:content_id).map(&:to_s)

            completed_content_ids = user_milestone.completed_content_ids - archived_content_ids
            completed_content_ids_before_lockdown = user_milestone.completed_content_ids_before_lockdown - archived_content_ids
            participated_content_ids = user_milestone.participated_content_ids - archived_content_ids
            user_milestone.set({
              participated_content_ids: participated_content_ids,
              completed_content_ids_before_lockdown: completed_content_ids_before_lockdown,
              completed_content_ids: completed_content_ids
            })

            user_journey = Timeline::UserJourney.find user_milestone.user_journey_id

            participated_content_ids = user_journey.participated_content_ids - archived_content_ids
            completed_content_ids = user_journey.completed_content_ids - archived_content_ids

            user_journey.set(
              participated_content_ids: participated_content_ids,
              completed_content_ids: completed_content_ids,
              participation_percentage: user_journey.calc_participation_percentage,
              completion_percentage: user_journey.calc_completion_percentage
            )
            milestone.update_leaderboard_for(user_milestone.reload.id)
          end
        end
      end
    end
  end
end