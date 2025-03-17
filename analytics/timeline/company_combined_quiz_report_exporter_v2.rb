module Analytics
  module Timeline
    class CompanyCombinedReportExporter < Analytics::BaseWorker
      attr_accessor :options, :user, :company, :company_journey_ids
      def perform(options)
        @options = options.with_indifferent_access
        RequestStore.store[:user_id] = options[:user_id]
        @user = RailsVger::AuthApi::User.api_show(options[:user_id])
        @company = RailsVger::AuthApi::Company.api_show(options[:company_id])
        @company_journey_ids = ::Timeline::Journey.where(company_id: options[:company_id]).pluck(:id)
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
            package.workbook.add_worksheet(name: 'Likeability') do |sheet|
              likeability_export_sheet(sheet)
            end
            create_journey_wise_export_sheet(package)
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
    
      def likeability_aggregation
        [{
          :$match => {
            'journey_id': { :$in => company_journey_ids },
            'user_profile_document.is_dummy' => false,
            :status => { :$in => ::Timeline::UserContent::NON_ARCHIVED_STATUSES }
          }
        },
        {
          :$group => {
            _id: {
              journey_id: '$journey_id'
            },
            milestone_id: { :$first => '$milestone_id' },
            journey_id: { :$first => '$journey_id' },
            user_content_count: { :$sum => 1 },
            disliked_count: {
              :$sum => {
                :$cond => [{ :$eq => ['$is_liked', false] }, 1, 0]
              }
            },
            liked_count: {
              :$sum => {
                :$cond => [{ :$eq => ['$is_liked', true] }, 1, 0]
              }
            },
            feedbacks_count: {
              :$sum => {
                :$cond => [{ :$in => ['$is_liked', [true, false]] }, 1, 0]
              }
            },
            completed_user_content_count: {
              :$sum => {
                :$cond => [{
                  :$eq => ['$status', 'completed']
                }, 1, 0]
              }
            },
          }
        },
        {
          :$project => {
            milestone_id: 1,
            feedbacks_count: 1,
            liked_by: 1,
            disliked_count: 1,
            user_content_count: 1,
            completed_user_content_count: 1,
            journey_id: 1,
            likeability: {
              :$multiply => [
                {
                  :$divide => [
                    '$liked_count',
                    {
                      :$cond => [
                        {
                          :$gt => [
                            '$feedbacks_count',
                            0
                          ]
                        },
                        '$feedbacks_count',
                        1
                      ]
                    }
                  ]
                },
                100
              ]
            }
          }
        },
        {
          :$lookup => {
            from: 'timeline_journies',
            localField: 'journey_id',
            foreignField: '_id',
            as: 'journey'
          }
        },
        {
          :$project => {
            liked_by: 1,
            likeability: {
              :$trunc => '$likeability'
            },
            feedbacks_count: 1,
            user_content_count: 1,
            completed_user_content_count: 1,
            journey: { :$arrayElemAt => ['$journey', 0] }
          }
        },
        {
          :$project => {
            liked_by: 1,
            likeability: 1,
            feedbacks_count: 1,
            user_content_count: 1,
            completed_user_content_count: 1,
            cp: 1,
            name: '$journey.name',
            competency_documents: '$journey.competency_documents'
          }
        }]
      end
    
      def likeability_export_sheet sheet
        sheet.add_row([
          'Development Program', 'Likeability'
        ], style: add_header_style(sheet))
        cell_style = add_cell_styles(sheet)
        ::Timeline::UserContent.collection.aggregate(likeability_aggregation).each do |record|
          sheet.add_row([
            record['name'],
            get_likability(record),
          ], style: cell_style)
        end
      end
    
      def get_likability(record)
        if record['feedbacks_count'] == 0
          return '-'
        elsif record['feedbacks_count']!= 0 && record['liked_by'] == 0
          return '0'
        else
          return record['likeability'].round(2)
        end 
      end
    
      def user_attributes user_journey
        user_profile = user_journey.user_profile_document
        ['name', 'email'].map do |key|
          user_profile['user_document'][key] rescue 'NA'
        end + [ 'business' ].map do |key|
          user_profile['custom_attributes'][key] rescue 'NA'
        end + [user_journey.journey_document['name']]
      end

      def create_journey_wise_export_sheet(package)
        package.workbook.add_worksheet(name: "Quiz Response") do |sheet|
          export_quiz_response(sheet)
        end
      end
    
      def export_quiz_response(sheet)
        journey_ids = ::Timeline::Journey.where(company_id: options[:company_id]).pluck(:id)
        competency_names = ::Timeline::Journey.where(
          company_id: options[:company_id]
        ).pluck(:'competency_documents.name').flatten.map{|c| c['name']}.uniq
        sheet.add_row([
          'Name', 'Email', 'Business', 'Journey Name',
          competency_names.map{|competency_name| [competency_name, 'Quiz Max Score']}
        ].flatten, style: add_header_style(sheet))

        user_profile_ids = ::Timeline::UserJourney.non_archived.where(
          :journey_id.in => journey_ids
        ).pluck(:user_profile_id).uniq


        cell_style = add_cell_styles(sheet)

        user_profile_ids.each do |user_profile_id|
          puts "User Profile id : #{user_profile_id}"
          uj = ::Timeline::UserJourney.non_archived.where(user_profile_id: user_profile_id).last
          next if uj.nil?
          user_row = user_attributes(uj)
          competency_quiz_scores = competency_names.map do |competency_name|
            uc = ::Timeline::UserContent.non_archived.where(
              :journey_id.in => journey_ids,
              user_profile_id: user_profile_id,
              'content_document.content_type' => 'quiz',
              'content_document.competency_document.name' => competency_name
            ).last
            if uc.present?
              [uc.score, uc.content.questions.sum(:max_score)]
            else
              ['', '']
            end
          end
          sheet.add_row([user_row,competency_quiz_scores].flatten, style: cell_style)
        end
      end
    end
  end
end

options = {user_id: '5d8b42f46bdb00de0efad141', company_id: '66c496fb695d8cee6a6bb5bf'}
# options = {company_id: '661626ba15a9ef001c2e1192'}
Analytics::Timeline::CompanyCombinedReportExporter.new.perform(options)
