module Analytics
  class AccountDetailExporter < ::BaseWorker
    attr_accessor :options, :user
    def perform(options)
      @options = options
      RequestStore.store[:user_id] = options[:user_id]
      @user = User.find(options[:user_id])
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
      file_name = "Account_Wise_Journey_#{Time.now.to_fs(:underscored)}_#{SecureRandom.hex(6)}.xlsx"
      file_path = "/tmp/#{file_name}"
      begin
        Axlsx::Package.new do |package|
          package.workbook.add_worksheet(name: 'Account Detail') do |sheet|
            create_export_sheet_for(sheet)
          end
          package.serialize(file_path)
        end
        AnalyticsMailer.send_report({
          subject: 'Account Details',
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
        'Account Name', 'Account Type', 'Creation Date',	'Total Users'
      ])

      company_ids = Company.active.pluck(:id)
      company_ids.each do |company_id|
        company = Company.find company_id
        sheet.add_row([
          company.name, (company.is_idev? ? 'iDev Journey' : 'iDev Plus'), company.created_at, UserProfile.where(company_id: company_id).not_suspended.count
        ])
        puts "#{company.id}"
      end
    end
  end
end

options = {user_id: '66580e9905d2660008129935'}
Analytics::AccountDetailExporter.new.perform(options)
