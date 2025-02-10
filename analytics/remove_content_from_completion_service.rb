class RemoveContentFromCompletionService < ApplicationService
  attr_accessor :content
  def initialize(content_id)
    @content = Timeline::Content.find(content_id)
  end

  def call()
    udpate_completion_percentage()
  end

  def udpate_completion_percentage()
    milestone = @content.milestone

    milestone.user_milestones.each do |user_milestone|
      update_completion_for_user_milestone(user_milestone)
    end
  end

  def update_completion_for_user_milestone(user_milestone)
    puts "Updating completion for user #{user_milestone.user_profile_document['user_document']}"
    user_milestone.send :update_milestone_stats
    user_milestone.save!
    user_journey = user_milestone.user_journey

    content_ids = user_journey.get_content_ids_for_scope({})

    participated_content_ids = user_journey.user_milestones.pluck(:participated_content_ids).flatten

    completed_content_ids = user_journey.user_milestones.pluck(:completed_content_ids).flatten

    user_journey.set(
      participated_content_ids: participated_content_ids,
      completed_content_ids: completed_content_ids
    )
  end
end

RemoveContentFromCompletionService.call(c.id)
