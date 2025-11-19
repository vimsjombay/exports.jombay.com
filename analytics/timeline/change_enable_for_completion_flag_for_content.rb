content_ids = ['68cd5de30eba3800026f0f7c', '68cd5dee0eba3800026f0f81']


def update_user_milestones_completions milestone
  puts "Updating User Milestones"
  total = milestone.user_milestones.count
  milestone.user_milestones.pluck(:id).each_with_index do |user_milestone_id, index|
    puts "#{index + 1} of #{total}"
    user_milestone = Timeline::UserJourney::UserMilestone.find(user_milestone_id)
    user_milestone.send :update_milestone_stats
  end
  puts "Done!"
end

content_ids.each do |content_id|
  content = Timeline::Content.find(content_id)
  puts content.title, content.enable_for_completion
  content.enable_for_completion = false
  content.save!
  sleep(3)
  puts content.title
  puts content.enable_for_completion
  update_user_milestones_completions(content.milestone)
end