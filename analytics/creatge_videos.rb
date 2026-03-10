user_assessment = AsyncInterview::UserAssessment.find('699315f0fc6858d4127034f6')
user_responses = user_assessment.user_responses.where(status: "pending")

user_responses.each do |response|
  folder = "sellers/5fec67a3e37a1d0ea58e59d4/companies/690ad7519d65e283719b55d6/async_interview/assessments/6991f76cf21cc443af610f74/user_assessments/#{user_assessment.id.to_s}/questions/#{response.question_id.to_s}/"
  
  response.s3_bucket = "client-content-production"
  response.s3_key = "eu-central-1"

  s3_region = response.s3_key
  s3_utils = JombayCore::Utils::S3Utils.using_region(s3_region)
  files = s3_utils.list_files(response.s3_bucket, folder)
  
  video_keys = files.select { |f| f.end_with?('.mp4') || f.end_with?('.webm') }
  video_key = video_keys.reject { |f| f.include?('original') }.first



  raise "Could not find mp4 video for question #{response.question_id}" if video_key.nil?

  response.save

cdn_url = "https://cdn-client-content.jombay.com/#{video_key}"
response.videos.create(
  cdn_url: cdn_url, 
  s3_bucket: 'client-content-production',
  s3_region: 'eu-central-1',
  s3_key: video_key,
  time_taken: 132,
  upload_time: 25.2,
)

response.status = "submitted"
response.save