module Analytics
  class ModuleWiseCompletionStatusExporter < Analytics::BaseWorker
    attr_accessor :options, :user, :company
    def perform(options)
      @options = options
      RequestStore.store[:user_id] = options[:user_id]
      @user = RailsVger::AuthApi::User.api_find(options[:user_id])
      @company = RailsVger::AuthApi::Company.api_find(options[:company_id])
      create_package()
    end

    def create_package()
      now = Time.now
      file_name = "ModuleWiseCompletionStatus#{Time.now.to_fs(:underscored)}.xlsx"
      file_path = "/tmp/#{file_name}"
      begin
        Axlsx::Package.new do |package|
          package.workbook.add_worksheet(name: 'Content wise status') do |sheet|
            create_export_sheet(sheet)
          end
          package.serialize(file_path)
        end
        AnalyticsMailer.send_report({
          subject: "Content wise data for #{company.name}",
          body: "Your content wise status export for #{company.name} is attached",
          time_zone: user.time_zone,
          attachments: {
            files: [{
              name: file_name,
              path: file_path
            }]
          },
          receiver: {
            name: user.name,
            email: user.email
          }
        }).deliver!
      rescue StandardError => e
        puts e.message
        puts e.backtrace
        mail_exception(e)
      ensure
        File.delete(file_path)
      end
    end

    def create_export_sheet sheet
      content_names = ::Timeline::Content.where(company_id: options[:company_id]).pluck(:title).uniq
      content_ids = ::Timeline::Content.where(company_id: options[:company_id]).pluck(:id)
      journey_ids = ::Timeline::Journey.where(company_id: options[:company_id]).pluck(:id)
      user_profile_ids = ::Timeline::UserJourney.where(
        :journey_id.in => journey_ids
      ).pluck(:user_profile_id).uniq

      headers = ["Name", "User Name", "Development Program"]

      body = []
      headers = headers + content_names

      sheet.add_row(headers, style: add_header_style(sheet))

      cell_style = add_cell_styles(sheet)
      total_ids = user_profile_ids.count
      user_profile_ids.each_with_index do |user_profile_id, index|
        puts "#{index + 1} / #{total_ids}"
        ::Timeline::UserJourney.where(
          user_profile_id: user_profile_id,
          :journey_id.in => journey_ids
        ).non_archived.each do |user_journey|
          ud = user_journey.user_profile_document
          puts "Getting data for #{ud['user_document']['name']}"
          user_content_statusses = get_attributes(ud) + [user_journey.journey_document['name']]
          content_names.each do |content_tile|
            user_content = ::Timeline::UserContent.non_archived.where(
              'content_document.title': content_tile,
              user_profile_id: user_profile_id,
              :content_id.in => content_ids
            ).first
            if(user_content.nil? || user_content.archived?)
              user_content_statusses << "NA"
            else
              user_content_statusses << user_content.status
            end
          end
          sheet.add_row(user_content_statusses, style: cell_style)
        end
      end
    end

    def get_attributes document, attrs = ['name', 'username']
      attrs.map {|at| document['user_document'][at] rescue '' }
    end

    def user_profile_info upd
      parant_document = upd['parent_document'];
      get_attributes(upd) + get_attributes(parant_document)
    end
  end
end

options = {user_id: '66580e9905d2660008129935', company_id: '654cbd16e7557b0008057618'}

Analytics::ModuleWiseCompletionStatusExporter.new.perform(options)

# Abhijit Tharot
# options = {user_id: '64e89bdc3c5ebb00082310d1', company_id: '654cbd16e7557b0008057618'}

# Akash Shinde

# Mine
# options = { user_id: '5d8b42f46bdb00de0efad141', company_id: '654cbd16e7557b0008057618'}
