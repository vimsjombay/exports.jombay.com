class UpdateManagerForLearner < ::BaseWorker
  attr_accessor :options
  def perform(options)
    @options = options.with_indifferent_access
    update()
  end

  def update
    options[:learners].each do |hash|
      puts hash
      learner = UserProfile.where(company_id: hash['company_id'], 'user_document.username' => hash['email']).not_suspended.last
      manager = UserProfile.where(company_id: hash['company_id'], 'user_document.username' => hash['manager_email']).not_suspended.last
      next unless learner.present? || manager.present?
      puts "Updating Learner #{hash['email']} manager #{hash['manager_email']}"
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
    email: 'ankit.kumar@pernod-ricard.com',
    manager_email: 'test.user+manager123@jombay.com',
    company_id: '6981d9451a7ec7e02804588d'
  },{
    email: 'lalit.kumar@pernod-ricard.com',
    manager_email: 'test.user+manager123@jombay.com',
    company_id: '6981d9451a7ec7e02804588d'
  }]
}

UpdateManagerForLearner.new.perform(options)
