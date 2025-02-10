
class Analytics::CompanyLikeabilityExporter < Analytics::BaseWorker
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
    file_name = "Company_likeability_#{Time.now.to_fs(:underscored)}.xlsx"
    file_path = "/tmp/#{file_name}"
    begin
      Axlsx::Package.new do |package|
        package.workbook.add_worksheet(name: 'Journey wise likeability') do |sheet|
          export_journey_likeability(sheet)
        end
        package.serialize(file_path)
      end
      AnalyticsMailer.send_report({
        subject: "Journey wise likeability for #{company.name}",
        body: "Your Journey wise likeability for #{company.name} is attached",
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
  def export_journey_likeability(sheet)
    sheet.add_row(['JOURNEY NAME', 'COMPETENCY NAME', 'LIKEABILITY %'])
    result = UserContent.collection.aggregate(aggregation_query)

    result.each do |record|
      journey = Journey.find record['journey_id']
      sheet.add_row([
        journey.name,
        journey.competency_document['name'],
        record['likeability'].round(2)
      ])
    end
  end

  def aggregation_query
    [{
      :$match => {
        'user_profile_document.company_document._id': options[:company_id],
        'user_profile_document.is_dummy' => false,
        :status => { :$in => ::UserContent::NON_ARCHIVED_STATUSES }
      }
    }, {
      :$group => {
        _id: {
          journey_id: '$journey_id'
        },
        journey_id: { :$first => '$journey_id' },
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
        }
      }
    }, {
      :$project => {
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
    }]
  end
end
options = {company_id: '64c0a35664c23a0008499691', user_id: '623d564ff67d8500092bfbcb'}
Analytics::CompanyLikeabilityExporter.new.perform(options)

options = {company_id: '64c0a35664c23a0008499691', user_id: '5d8b42f46bdb00de0efad141'}
