Timeline::Journey.where(:created_at.gte => Time.now - 10.months).each do |journey|
  puts "Journey: #{journey.id}"
  journey.milestones.each do |milestone|
    puts "Generating leaderboard for #{milestone.name}"
    total = milestone.user_milestones.count
    milestone.user_milestones.each_with_index do |user_milestone, index|
      puts "User Milestone #{index + 1} of #{total}"
      milestone.update_leaderboard_for(user_milestone.reload.id)
    end
  end
end