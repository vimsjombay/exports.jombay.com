
content_ids = [
  '688c893b5345140002bb033f',
  '688c89775345140002bb034e',
  '688c89c89dcca900020a160e',
  '688c8a219dcca900020a164c'
].freeze

competency_id = '68b57c2ba9b7590002739c69'

competency = Timeline::Journey::Competency.find competency_id
puts competency.name
content_ids.each do |content_id|
  content = Timeline::Content.find content_id
  puts content.title
  content.competency = competency
  content.save!
end

