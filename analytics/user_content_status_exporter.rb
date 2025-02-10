module Analytics
  class UserContentStatusExporter < Analytics::BaseWorker
    attr_accessor :options, :user, :company, :usernames
    def perform(options)
      @options = options
      RequestStore.store[:user_id] = options[:user_id]
      @user = RailsVger::AuthApi::User.api_find(options[:user_id])
      @company = RailsVger::AuthApi::Company.api_find(options[:company_id])
      @usernames = options[:usernames] || []
      create_package()
    end

    def create_package()
      now = Time.now
      file_name = "User_Content_Status_#{Time.now.to_fs(:underscored)}.xlsx"
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
        File.delete(file_path) if File.exist?(file_path)
      end
    end

    def create_export_sheet sheet
      content_id_user_journey_ids = Timeline::UserContent.where(
        :'user_profile_document.user_document.username'.in => usernames,
      ).pluck(:content_id, :user_journey_id)
      puts "Total Record IDs: #{content_id_user_journey_ids.count}"
      content_ids = content_id_user_journey_ids.map(&:first).uniq
      user_journey_ids = content_id_user_journey_ids.map(&:last).uniq
      puts "Total Content IDs: #{content_ids.count}"
      puts "Total UserJourney IDs: #{user_journey_ids.count}"
      content_ids = Timeline::Content.where(
        :id.in => content_ids,
        company_id: options[:company_id]
      ).pluck(:id)
      puts "Total Content IDs(company): #{content_ids.count}"
      content_names = Timeline::Content.where(:id.in => content_ids).pluck(:title)

      user_profile_ids = Timeline::UserJourney.where(
        :id.in => user_journey_ids,
        'user_profile_document.company_document._id': options[:company_id]
      ).pluck(:user_profile_id).uniq

      puts "User Profile IDs: #{user_profile_ids.count}"
      headers = ["Name", "User Name", "Development Program"]

      body = []
      headers = headers + content_names + ['Completion Percentage', 'Contents Enabled for Completion', 'Completed Contents Count']

      sheet.add_row(headers, style: add_header_style(sheet))

      cell_style = add_cell_styles(sheet)
      total_ids = user_profile_ids.count
      user_profile_ids.each_with_index do |user_profile_id, index|
        puts "#{index + 1} / #{total_ids}: #{user_profile_id}"
        Timeline::UserJourney.where(
          user_profile_id: user_profile_id,
          :id.in => user_journey_ids
        ).non_archived.each do |user_journey|
          ud = user_journey.user_profile_document
          puts "Getting data for #{ud['user_document']['name']}"
          user_content_statusses = get_attributes(ud) + [user_journey.journey_document['name']]
          content_names.each do |content_tile|
            user_content = Timeline::UserContent.non_archived.where(
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
          user_content_statusses << user_journey.completion_percentage
          user_content_statusses << get_extra_colums(user_journey)
          # user_content_statusses << user_journey.calc_completion_percentage
          sheet.add_row(user_content_statusses.flatten, style: cell_style)
        end
      end
    end

    def get_extra_colums user_journey
      content_ids = user_journey.get_content_ids_for_scope({})
      total = content_ids.count

      completed = Timeline::UserContent.completed.where(
        :content_id.in => content_ids,
        user_journey_id: user_journey.id,
        :'content_document.is_manager_feedback_enabled'.ne => true
      ).count + Timeline::UserContent.completed.where(
        :content_id.in => content_ids,
        user_journey_id: user_journey.id,
        :'content_document.is_manager_feedback_enabled' => true,
        manager_feedback_status: 'completed'
      ).count
      [total, completed]
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

# Abhijit Tharot
options = {user_id: '64e89bdc3c5ebb00082310d1', company_id: '66506b8b156e8900085d37f9'}

# Akash Shinde
options = {user_id: '66580e9905d2660008129935', company_id: '66506b8b156e8900085d37f9'}

options = { user_id: '5d8b42f46bdb00de0efad141', company_id: '66506b8b156e8900085d37f9', usernames: usernames}
Analytics::UserContentStatusExporter.new.perform(options)

# Mine
