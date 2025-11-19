module Analytics
  class CompanyJourneyCompletionExporter < ::Analytics::BaseWorker
    attr_accessor :options, :user
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
      file_name = "Account_Wise_Journey_#{Time.now.to_fs(:underscored)}_#{SecureRandom.uuid}.xlsx"
      file_path = "/tmp/#{file_name}"
      begin
        Axlsx::Package.new do |package|
          package.workbook.add_worksheet(name: 'Account Detail') do |sheet|
            create_export_sheet_for(sheet)
          end
          package.serialize(file_path)
        end
        AnalyticsMailer.send_report({
          subject: 'Account wise journey completion',
          body: 'Your export account wise journey completion is attached to this email..',
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
        # File.delete(file_path) if File.exist?(file_path)
      end
    end

    def create_export_sheet_for sheet
      sheet.add_row([
        'Account Name', 'Completion'
      ])
      export_journey_completion(sheet, Timeline::Journey, Timeline::UserContent)
      export_journey_completion(sheet, Journey, UserContent)
    end

    def export_journey_completion(sheet,journey_klass, user_content_klass)
      company_ids = journey_klass.non_archived.pluck(:company_id).uniq
      company_ids.each do |company_id|
        puts "Company ID: #{company_id}"
        journey_ids = journey_klass.where(company_id: company_id).pluck(:id)
        journey = journey_klass.find(journey_ids.first)
        user_contents = user_content_klass.non_archived.where(
          :journey_id.in => journey_ids
        ).non_archived

        total = user_contents.count
        completed = user_contents.completed.count
        completion = 0
        completion = ((completed.to_f / total.to_f) * 100).round(2) if total > 0
        puts "Company ID: #{company_id} : #{total} : #{completed} : #{completion}"
        sheet.add_row([
          journey.company_document['name'],
          "#{completion}%"
        ])
      end
    end
  end
end

options = {user_id: '66580e9905d2660008129935'}
Analytics::CompanyJourneyCompletionExporter.new.perform(options)
