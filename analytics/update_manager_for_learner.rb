class UpdateManagerForLearner < ::BaseWorker
  attr_accessor :options
  def perform(options)
    @options = options.with_indifferent_access
    update()
  end

  def update
    options[:learners].each do |learner|
      puts learner
      learner = UserProfile.find_by 'user_document.email' => learner[:email]
      manager = UserProfile.find_by 'user_document.email' => learner[:manager_email]

      learner.set(parent_id: manager.id)
      parent_document = {
        _id: manager.id,
        user_document: manager.user_document
      }
      learner.set(parent_document: parent_document)
    end
    puts 'Done!'

    verify_update
  end

  def verify_update
    options[:learners].each do |learner|
      puts learner
      learner = UserProfile.find_by 'user_document.email' => learner[:email]
      puts learner.parent_document['user_document']['email'] == learner[:manager_email]
    end
  end
end

options = {learners: [{
  email: 'muralidharap@nsdl.com',
  manager_email: 'vaishaliv@nsdl.com'
}, {
  email: 'chetanm@nsdl.com',
  manager_email: 'rakeshk@nsdl.com'
}]}
UpdateManagerForLearner.new.perform(options)
