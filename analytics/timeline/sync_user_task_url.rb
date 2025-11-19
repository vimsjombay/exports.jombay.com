class SyncUserTaskUrl
  def self.call task_id, user_emails
    content = Timeline::Content.find(task_id)
    sync_user_exercises_data content, user_emails
  end

  def self.sync_user_exercises_data content,user_emails
    user_ids = content.user_contents.where(
      'user_profile_document.user_document.email' => { '$in' => user_emails}
    ).pluck(:user_profile_document).map{|upd| upd['user_document']['_id']}
    conditions = {
      exercise_id: content.task_id,
      scopes: {
        non_archived: '',
      },
      joins: [:user],
      include: {
        user: {
          only: [:authapi_id]
        }
      },
      methods: [:system_check_url],
      order: "id asc"
    }
    syncing_count = 0
    user_ids.each_slice(50).with_index do |user_ids_slice, _index|
      syncing_count += user_ids_slice.size
      # puts "Sync  #{syncing_count} of #{user_ids.count}"
      conditions[:query_options] = {
        "jombay_users.authapi_id": user_ids_slice
      }
      # puts conditions
      user_exercises_slice = RailsVger::AssessmentApi::Oac::UserExercise.api_index(
        conditions
      ).to_a
      puts user_exercises_slice
      user_exercises_slice.each do |user_exercise|
        puts user_exercise
        uc = content.user_contents.where(
          "user_profile_document.user_document._id" => user_exercise.user.authapi_id
        ).last
        uc.update!({
          task_url: user_exercise.system_check_url,
          synced: {}
        })
        puts "System check url--------#{uc.id}: #{uc.user_profile_document['user_document']['email']}"
        puts user_exercise.system_check_url
      end
    end
    puts "DONE!"
  end
end

user_emails = [
  "boju.kp143@gmail.com",
  "vidhya.shettar@gmail.com",
  "neethu51189@gmail.com",
  "ssumanjangir@gmail.com",
  "soumya.tvm.ss@gmail.com",
  "75.divya@gmail.com",
  "meenakshi0228@gmail.com",
  "vandnakakkar@gmail.com",
  "sarika.teke@angelone.in",
  "rinki.roy97@gmail.com"
]

SyncUserTaskUrl.call('687a2bb99fb83c00025ac3e9', user_emails)

user_emails =[
  "vandnakakkar@gmail.com",
  "sarika.teke@angelone.in",
  "rinki.roy97@gmail.com"
]
SyncUserTaskUrl.call('687a2b294061100002632bd2', user_emails)


user_emails =[
  'ranasonam14@gmail.com',
  'gloria.dsilva@crisil.com',
  'harshirohi121@gmail.com'
]

user_emails.each do |email|
  authapi_user = RailsVger::AuthApi::User.api_index({query_options: {email: email}}).first
  user = User.find_by email: email
  user.authapi_id = authapi_user.id
  user.update! authentication_token: authapi_user.authentication_token
end