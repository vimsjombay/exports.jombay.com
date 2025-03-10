module Analytics
  class CompanySurveyExporter < Analytics::BaseWorker
    attr_accessor :options, :user, :manager_token_mapping
    def perform(options)
      @options = options
      RequestStore.store[:user_id] = options[:user_id]
      @user = RailsVger::AuthApi::User.api_find(options[:user_id])
      @manager_token_mapping = {}
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
      file_name = "Feedback_Status_#{Time.now.to_fs(:underscored)}_#{SecureRandom.hex(6)}.xlsx"
      file_path = "/tmp/#{file_name}"
      begin
        Axlsx::Package.new do |package|
          package.workbook.add_worksheet(name: 'Survey Report') do |sheet|
            create_export_sheet(sheet)
          end
          package.serialize(file_path)
        end
        AnalyticsMailer.send_report({
          subject: 'Feedbacks Export for ABG',
          body: 'Your export for surveys ready and attached to this email..',
          time_zone: user.try(:time_zone),
          attachments: {
            files: [{
              name: file_name,
              path: file_path
            }]
          },
          receiver: reciever_data
        }).deliver!
      rescue => e
        puts e.message
        puts e.backtrace
        #mail_exception(e)
      ensure
        File.delete(file_path) if File.exist?(file_path)
      end
    end

    def create_export_sheet sheet
      sheet.add_row([
        'Participant Name', 'Username', 'Manager Name',	'Manager Username', 'Business',	'Competency Name',	'Journey Name',	'Module Name',	'Learner Survey Completion Status',	'Learner Rating',	'Manager Survey Completion Status',	'Manager Rating', "Feedback Links"
      ], style: add_header_style(sheet))

      cell_style = add_cell_styles(sheet)
      user_content_ids = UserContent.where(
        'user_profile_document.company_document._id' => options[:company_id],
        'content_document.content_type' => 'feedback'
      ).non_archived.pluck(:id)
      total = user_content_ids.size
      user_content_ids.each_with_index do |user_content_id, index|
        uc = UserContent.find user_content_id
        puts "#{index + 1} of #{total} : #{uc.user_profile_document['user_document']['name']}"
        sheet.add_row([
          user_profile_info(uc.user_profile_document),
          uc.journey.competency_document['name'],
          uc.journey.name,
          uc.content_document['title'],
          uc.status,
          uc.score,
          uc.manager_feedback_status,
          uc.manager_feedback_score,
          get_manager_feedback_link(uc)
        ].flatten, style: cell_style)
      end
    end

    def get_attributes document, attrs = ['name', 'username']
      attrs.map {|at| document['user_document'][at] rescue '' }
    end

    def get_custom_attributes document, attrs = ['business']
      attrs.map {|at| document[at] rescue '' }
    end

    def user_profile_info upd
      parant_document = upd['parent_document'];
      get_attributes(upd) + get_attributes(parant_document) + get_custom_attributes(upd['custom_attributes'])
    end

    def get_manager_feedback_link uc
      manager_document = uc.user_profile_document['parent_document']
      return '' if manager_document.nil?
      user_id = manager_document['user_document']['_id']
      if manager_token_mapping[user_id].nil?
        manager = RailsVger::AuthApi::User.api_find(user_id)
        manager_token_mapping[user_id] = manager.authentication_token
      end
      auth_token = manager_token_mapping[user_id]
      [
        "#{ENV['IDEV_URL']}/companies/#{options[:company_id]}/manager",
        "/feedback/#{uc.content_id}?auth_token=#{auth_token}"
      ].join('')
    rescue => e
      puts e.message
      puts e.backtrace
      ''
    end
  end
end

options = {user_id: '66580e9905d2660008129935', company_id: '64c0a35664c23a0008499691'}
Analytics::CompanySurveyExporter.new.perform(options)
