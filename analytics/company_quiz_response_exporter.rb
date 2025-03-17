
class Analytics::CompanyQuizResponseExporter < Analytics::BaseWorker
  attr_accessor :options, :user, :company
  def perform(options)
    @options = options.with_indifferent_access
    RequestStore.store[:user_id] = options[:user_id]
    @user = RailsVger::AuthApi::User.api_find(options[:user_id])
    @company = RailsVger::AuthApi::Company.api_show(options[:company_id])
    create_package()
  end

  def reciever_data
    return { name: 'Test User', email: 'test.user@jombay.com' } if user.nil?
    {
      name: user.name,
      email: user.email
    }
  end

  def create_package()
    now = Time.now
    file_name = "quiz_response_#{Time.now.to_fs(:underscored)}.xlsx"
    file_path = "/tmp/#{file_name}"
    begin
      Axlsx::Package.new do |package|
        package.workbook.add_worksheet(name: 'Journey Report') do |sheet|
          export_quiz_response(sheet)
        end
        package.serialize(file_path)
      end
      AnalyticsMailer.send_report({
        subject: "Quiz responses for #{company.name}",
        body: "Your quiz response export for #{company.name} is attached",
        time_zone: user.try(:time_zone),
        attachments: {
          files: [{
            name: file_name,
            path: file_path
          }]
        },
        receiver: reciever_data
      }).deliver!
    rescue StandardError => e
      puts e.message
      puts e.backtrace
      mail_exception(e)
    ensure
      File.delete(file_path)
    end
  end
  
  def user_attributes user_content
    user_profile = RailsVger::AuthApi::UserProfile.api_find(user_content.user_profile_id)
    ['name', 'username', 'email'].map do |key|
      user_profile['user_document'][key]
    end + ['name', 'username', 'email', 'mobile'].map do |key|
      user_profile['parent_document']["user_document"][key] rescue 'NA'
    end + [ 'business', 'employee_id' ].map do |key|
      user_profile['custom_attributes'][key] rescue 'NA'
    end + [
      user_profile.group_documents.map{|g| g['name']}.join('|')
    ]
  end

  def export_quiz_response(sheet)
    sheet.add_row([
      'Name','Username', 'Email', 'Manager name', 'Manager Username', 'Manager email',
      'Manager mobile', 'Business', 'Employee ID', 'Groups', 'Competency Name',
      'Journey Name', 'Quiz Title', 'Quiz Status', 'Quiz Max Score', 'Quiz Score'
    ])

    UserContent.where(
      'user_profile_document.company_document._id': options[:company_id],
      'content_document.content_type' => 'quiz'
    ).non_archived.each do |user_content|
      journey = user_content.journey
      puts user_content.id.to_s
      sheet.add_row([
        user_attributes(user_content),
        journey.competency_document['name'],
        journey.name,
        user_content.content_document['title'],
        user_content.status,
        user_content.content.questions.sum(:max_score),
        user_content.completed? ? user_content.score : '' 
      ].flatten)
    end
  end
end


options = {company_id: '64c0a35664c23a0008499691', user_id: '5d8b42f46bdb00de0efad141'}
Analytics::CompanyQuizResponseExporter.new.perform(options)

options = {company_id: '64c0a35664c23a0008499691', user_id: '623d564ff67d8500092bfbcb'}
