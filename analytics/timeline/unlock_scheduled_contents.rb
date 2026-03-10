Timeline::Content.where(:start_date.gte => Time.now, status: 'locked').each do |content|
  content.send :schedule_unlock_content
end

