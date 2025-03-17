module Analytics
  class CompanySurveyQuestionExporter < Analytics::BaseWorker
    attr_accessor :options, :user, :manager_token_mapping
    def perform(options)
      @options = options
      RequestStore.store[:user_id] = options[:user_id]
      @user = RailsVger::AuthApi::User.api_find(options[:user_id])
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
      file_name = "Survey_Export_for_iDev_Plus_#{Time.now.to_fs(:underscored)}_#{SecureRandom.hex(6)}.xlsx"
      file_path = "/tmp/#{file_name}"
      begin
        Axlsx::Package.new do |package|
          package.workbook.add_worksheet(name: 'Learner Export') do |sheet|
            create_export_sheet_for(sheet, 'question')
          end
          package.workbook.add_worksheet(name: 'Manager Export') do |sheet|
            create_export_sheet_for(sheet, 'manager_question')
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

    def create_manager_export sheet

    end

    def get_responses_for content, user_content, response_key
      responses = user_content.send("#{response_key}_responses")
      content.send(response_key.pluralize).pluck(:id).map do |question_id|
        resp = responses.where(question_id: question_id).first
        resp.try(:score) || 'NA'
      end
    end

    def get_question_headers(content, response_key)
      content.send(response_key.pluralize).pluck(:body)
    end

    def create_export_sheet_for sheet, response_key
      sheet.add_row([
        'Participant Name', 'Username', 'Manager Name',	'Manager Username', 'Business',	'Competency Name',	'Journey Name',	'Module Name',	'Learner Survey Completion Status',	'Learner Rating',	'Manager Survey Completion Status',	'Manager Rating'
      ].flatten, style: add_header_style(sheet))

      Content.where(
        company_id: options[:company_id],
        content_type: 'feedback'
      ).non_archived.pluck(:id).each do |content_id|
        content = Content.find content_id
        add_responses_for_content(content, sheet, response_key)
      end
    end

    def add_responses_for_content content, sheet, response_key
      sheet.add_row([
        '', '', '',	'', '',	'',	'',	'',	'',	'',	'',	'',
        get_question_headers(content, response_key)
      ].flatten, style: add_header_style(sheet))

      cell_style = add_cell_styles(sheet)

      user_content_ids = content.user_contents.non_archived.pluck(:id)
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
          get_responses_for(content, uc, response_key)
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
  end
end

options = {user_id: '5e045e7f3e1f216b2df06ee6', company_id: '64c0a35664c23a0008499691'}
Analytics::CompanySurveyQuestionExporter.new.perform(options)
