class UpdateManagerForLearner < ::BaseWorker
  attr_accessor :options
  def perform(options)
    @options = options.with_indifferent_access
    update()
  end

  def update
    options[:learners].each do |hash|
      puts hash
      learner = UserProfile.find_by 'user_document.username' => hash['email']
      manager = UserProfile.find_by 'user_document.username' => hash['manager_email']

      learner.set(parent_id: manager.id)
      parent_document = {
        _id: manager.id,
        user_document: manager.user_document
      }
      learner.set(parent_document: parent_document)
    end
    puts 'Done!'
  end
end

options = {
  learners: [{
    email: 'chandrashekhard@nsdl.com',
    manager_email: 'abhijeets@nsdl.com'
  }, {
    email: 'ravindrah@nsdl.com',
    manager_email: 'abhijeets@nsdl.com'
  },{
    email:'mahendrav@nsdl.com',
    manager_email: 'khilonab@nsdl.com'
  }]
}
UpdateManagerForLearner.new.perform(options)
