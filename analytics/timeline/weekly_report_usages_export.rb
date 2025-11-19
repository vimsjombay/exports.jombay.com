class Timeline::Analytics::Journies::WeeklyReportUsageReport < ::Timeline::Analytics::BaseWorker
  attr_accessor :parsed_date, :options, :user
  def perform(inputs)
    @parsed_date = DateTime.parse(inputs[:from])
    @options = inputs.with_indifferent_access
    @user = RailsVger::AuthApi::User.api_show(options[:user_id])
    create_report
  end

  def create_report
    file_name = "weekly_report_usage_analytics_#{Time.now.to_i}.xlsx"
    file_path = "/tmp/#{file_name}"
    begin
      Axlsx::Package.new do | package |
        create_export_sheet(package)
        package.serialize(file_path)
      end
      report_data = {
        subject: "iDev | Usage Tracking Report for Weekly Reports | #{current_date}",
        body: "Attached is the Usage Tracking Report for Weekly Reports.<br/>
        Duration: #{options[:from]} to #{current_date}",
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
      }
      AnalyticsMailer.send_report(report_data).deliver!

      File.delete(file_path)
    rescue => e
      # puts e.message
      # puts e.backtrace
      mail_exception(e)
    end
  end

  def current_date
    Time.now.strftime("%d/%m/%Y")
  end

  def create_export_sheet package
    package.workbook.add_worksheet(name: 'Summary') do |sheet|
      create_summary_export(sheet)
    end
    package.workbook.add_worksheet(name: 'Detailed Report') do |sheet|
      create_detailed_export(sheet)
    end
  end

  def create_summary_export sheet
    cell_style = add_cell_styles(sheet)
    res = Timeline::Journey::ScheduledJob.collection.aggregate(pipeline).first
    result = res.with_indifferent_access
    total_reports = result[:total_reports][0][:count]
    dashboard_count = result[:dashboard_reports][0][:count]
    summary_count = result[:summary_reports][0][:count]
    dp_report_count = result[:dp_reports][0][:count]
    lc_reports_count = result[:learner_completion_reports][0][:count]
    module_stat_count = result[:module_stats_reports][0][:count]
    competency_stat_count = result[:competency_stats_reports][0][:count]
    sheet_combos = result[:common_sheet_combinations].first[:_id]
    common_demographics = result[:common_demographic_filters].pluck(:_id)
    sheet.add_row(["Total Reports Generated", total_reports], style: cell_style)
    sheet.add_row(["Reports with Dashboard", dashboard_count], style: cell_style)
    sheet.add_row(["Reports with Summary", summary_count], style: cell_style)
    sheet.add_row(["Reports with DP Report", dp_report_count], style: cell_style)
    sheet.add_row(["Reports with Learner-wise Completion", lc_reports_count], style: cell_style)
    sheet.add_row(["Reports with Module Stats", module_stat_count], style: cell_style)
    sheet.add_row(["Reports with Competency Stats", competency_stat_count], style: cell_style)
    sheet.add_row(["Common Sheet Combinations", sheet_combos.join(', ')], style: cell_style)
    sheet.add_row(["Common Demographic Filters", common_demographics&.join(', ')], style: cell_style)
  end

  def create_detailed_export sheet
    cell_style = add_cell_styles(sheet)
    sheet.add_row([
      'Report Name',
      'Created At',
      'User',
      'Email',
      'Company Name',
      'DP Name',
      'Sheets Included',
      'Selected Demographic Filters',
      'Scale for Dashboard',
      'Scale for Development Program Report',
      'Scale for Learnerwise Completion Report',
      'Frequency',
      'Scheduled Days',
      'Scheduled Time',
      'Start Date',
      'End Date',
      'Email From',
      'Email To',
      'DP Timeline Authoring Link',
      'Weekly Report Link'
    ],style: add_header_style(sheet))
    
    ::Timeline::Journey::ScheduledJob.where(status: 'active', :created_at.gte => parsed_date).pluck(:id).each do |job_id|
      scheduled_job = ::Timeline::Journey::ScheduledJob.find job_id
      sheet.add_row([
        scheduled_job.name,
        Time.parse(scheduled_job.created_at.in_time_zone(user.time_zone).to_s).strftime("%Y-%m-%d %H:%M:%S"),
        scheduled_job.creator_document['user_document']['name'],
        scheduled_job.creator_document['user_document']['email'],
        scheduled_job.journey.company_document['name'],
        scheduled_job.journey.name,
        scheduled_job.sheet_configuration.keys.join(', '),
        get_demographic_filters(scheduled_job),
        get_sheet_scales(scheduled_job),
        scheduled_job.frequency,
        scheduled_job.schedule_days.map { |day| Date::DAYNAMES[day.to_i] }.join(', '),
        scheduled_job.schedule_time,
        Time.parse(scheduled_job.start_date.in_time_zone(user.time_zone).to_s).strftime("%Y-%m-%d %H:%M:%S"),
        Time.parse(scheduled_job.end_date.in_time_zone(user.time_zone).to_s).strftime("%Y-%m-%d %H:%M:%S"),
        scheduled_job.email_config['from_email_id'],
        scheduled_job.email_config['to'],
        dp_link(scheduled_job),
        weekly_report_link(scheduled_job)
      ].flatten,style: cell_style)
    end
  end

  def get_demographic_filters scheduled_job
    dashboard = scheduled_job.sheet_configuration['Dashboard']
    return 'NA' unless dashboard
    return dashboard['demographic_filters'].join(', ') if dashboard['demographic_filters']
    return 'NA'
  end

  def dp_link scheduled_job
    [
      ENV.fetch('IDEV_AUTHORING_URL'),
      'companies',
      scheduled_job.journey.company_id,
      'timeline/journies',
      scheduled_job.journey.id,
    ].join('/')
  end

  def weekly_report_link scheduled_job
    [ ENV.fetch('COMMUNICATION_DASHBOARD_URL'),
      'companies',
      scheduled_job.journey.company_id, 
      'journies',
      scheduled_job.journey_id,
      'weekly-report?tab=active'].join('/')
  end

  def get_sheet_scales scheduled_job
    scales = [] 
    if scheduled_job.sheet_configuration.keys.include?('Dashboard')
      scale_string = scale_to_string(scheduled_job.sheet_configuration['Dashboard']['scale'])
      if scheduled_job.sheet_configuration['Dashboard']['apply_to_learner_wise_sheet_and_development_program_report']
        3.times { scales << scale_string }
      else
        scales << scale_string
      end
    else
      scales << 'NA'
    end
    unless scheduled_job.sheet_configuration.dig('Dashboard', 'apply_to_learner_wise_sheet_and_development_program_report')
      ["Learner Wise Completion", "Development Program Report"].each do |sheet_key|
        if scheduled_job.sheet_configuration.key?(sheet_key) &&
           scheduled_job.sheet_configuration[sheet_key]['scale']
          scale_string = scale_to_string(scheduled_job.sheet_configuration[sheet_key]['scale'])
          scales << scale_string
        else
          scales << "NA"
        end
      end
    end
    return scales
  end

  def scale_to_string(scale)
    scale.sort_by { |_label, range| range["from"] }.map do |label, range|
      from = range["from"]
      to = range["to"]
      "#{from} < #{label.capitalize} < #{to}"
    end.join(", ")
  end

  def pipeline
    [
      {
        :$match => {
          created_at: { :$gte => parsed_date },
          status: 'active'
        }
      },
      {
        :$facet => {
          "from_date": [
            {
              :$group => {
                "_id": nil,
                "min_date": { :$min => "$created_at" }
              }
            }
          ],
          "total_reports": [
            { :$count => "count" }
          ],
          "dashboard_reports": [
            {
              :$match => {
                "sheet_configuration.Dashboard": { :$exists => true, :$ne => nil }
              }
            },
            {
              :$group => {
                _id: nil, 
                count: {:$sum => 1}
              }
            }
          ],
          "summary_reports": [
            {
              :$match => {
                "sheet_configuration.Summary": { :$exists => true, :$ne => nil }
              }
            },
            { :$count => "count" }
          ],
          "dp_reports": [
            {
              :$match => {
                "sheet_configuration.Development Program Report": { :$exists => true, :$ne => nil }
              }
            },
            { :$count => "count" }
          ],
          "learner_completion_reports": [
            {
              :$match => {
                "sheet_configuration.Learner Wise Completion": { :$exists => true, :$ne => nil }
              }
            },
            { :$count => "count" }
          ],
          "module_stats_reports": [
            {
              :$match => {
                "sheet_configuration.Module Stats": { :$exists => true, :$ne => nil }
              }
            },
            { :$count => "count" }
          ],
          "competency_stats_reports": [
            {
              :$match => {
                "sheet_configuration.Competency Stats": { :$exists => true, :$ne => nil }
              }
            },
            { :$count => "count" }
          ],
          "common_sheet_combinations": [
            {
              :$project => {
                :sheet_names => { :$objectToArray => "$sheet_configuration" }
              }
            },
            {
              :$project => {
                :sheet_names => {
                  :$map => {
                    :input => "$sheet_names",
                    :as => "s",
                    :in => "$$s.k"
                  }
                }
              }
            },
            {
              :$project => {
                :sorted_sheet_names => { :$sortArray => { :input => "$sheet_names", :sortBy => 1 } }
              }
            },
            {
              :$group => {
                :_id => "$sorted_sheet_names",
                :count => { :$sum => 1 }
              }
            },
            { :$sort => { :count => -1 } },
            { :$limit => 5 }
          ],
          "common_demographic_filters": [
            {
              :$match => {
                "sheet_configuration.Dashboard.demographic_filters": { :$exists => true, :$ne => nil }
              }
            },
            {
              :$project => {
                :demographic_filters => "$sheet_configuration.Dashboard.demographic_filters"
              }
            },
            { :$unwind => "$demographic_filters" },
            {
              :$group => {
                :_id => "$demographic_filters",
                :count => { :$sum => 1 }
              }
            },
            { :$sort => { :count => -1 } },
            { :$limit => 5 }
          ]
        }
      }
    ]
  end
end

Timeline::Analytics::Journies::WeeklyReportUsageReport.new.perform({
  from: '16/05/2025',
  user_id: '66f3a6266ac049ff993c0b59'
})