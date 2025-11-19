class Timeline::Analytics::Journies::CommunicationUsageExporter < ::Timeline::Analytics::BaseWorker
  attr_accessor :options, :user, :from_date
  def perform(options)
    @options = options.with_indifferent_access
    @user = RailsVger::AuthApi::User.api_show(options[:user_id])
    @from_date = Date.strptime(options[:start_date], "%d/%m/%Y").beginning_of_day
    create_report
  end

  def create_report
    file_name = "communication_usage_analytics_#{Time.now.to_i}.xlsx"
    file_path = "/tmp/#{file_name}"
    begin
      Axlsx::Package.new do | package |
        create_export_sheet(package, options)
        package.serialize(file_path)
      end
      report_data = {
        subject: "iDev | Usage Tracking Report for Scoring Communication and Dynamic Certificates | #{current_date}",
        body: "Attached is the Usage Tracking Report for Scoring Communication and Dynamic Certificates.<br/>
        Duration: #{options[:start_date]} to #{current_date}",
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

  def create_export_sheet package, options
    package.workbook.add_worksheet(name: 'Summary') do |sheet|
      create_summary_export(sheet)
    end
    package.workbook.add_worksheet(name: 'Detailed Report') do |sheet|
      create_detailed_export(sheet)
    end
  end

  def create_summary_export sheet
    cell_style = add_cell_styles(sheet)
    communication_summary = ::Timeline::Journies::ScoringCommunicationAggregationService.new({
      start_date: from_date
    }).call
    template_stats = RailsVger::ReportGenerator::Idev::Certificate.api_analytics_data({
      start_date: from_date
    })
    sheet.add_row([
      "No. of Communications Sent",
      Timeline::Journey::ScoringCommunication.where(status: "sent", :created_at.gte => from_date).count
    ], style: cell_style)
    sheet.add_row([
      "No. of Communications Used for Certificate Distribution",
      communication_summary[:total_communications_sent] | 0
    ], style: cell_style)
    sheet.add_row([
      "No. of Certificate Templates Created",
      template_stats.created_templates | 0
    ], style: cell_style)
    sheet.add_row([
      "No. of Certificate Templates Replicated",
      template_stats.total_times_replicated | 0
    ], style: cell_style)
    sheet.add_row([
      "No. of Certificate Templates Edited",
      template_stats.updated_templates | 0
    ], style: cell_style)
    sheet.add_row([
      "Most Commonly Used Certificate Template",
      RailsVger::ReportGenerator::Idev::Certificate.api_show(communication_summary[:most_used_template])&.name
    ], style: cell_style)
  end

  def create_detailed_export sheet
    cell_style = add_cell_styles(sheet)
    sheet.add_row([
      'Template Name',
      'Orientation',
      'Includes Participant Name',
      'Includes Company Name',
      'Includes Participant Image',
      'Includes Logo',
      'Includes Custom Text',
      'Template Link',
      'Linked with Communication',
      'Scheduled Date',
      'Sent to No of Participants'
    ],style: add_header_style(sheet))
    
    ::Timeline::Journey::ScoringCommunication.where(status: 'sent', is_certificate_sending_enabled: true,  :created_at.gte => from_date).pluck(:id).each do |communication_id|
      communication = find_communication(communication_id)
      template = find_template(communication.certificate_template_id)

      sheet.add_row([
        template_details(template, communication),
        communication_url(communication),
        Time.parse(communication.scheduled_at.in_time_zone(user.time_zone).to_s).strftime("%Y-%m-%d %H:%M:%S"),
        communication.recipients_count
      ].flatten,style: cell_style)
    end
  end

  def template_details template, communication
    return [
      'NA',
      'NA',
      'NA',
      'NA',
      'NA',
      'NA',
      'NA',
      "#{ENV.fetch('REPORT_GENERATOR_URL')}/idev/templates/#{communication.certificate_template_id}"
    ] if template.nil?
    [
      template.name,
      template.orientation,
      custom_fields_included(template),
      template.has_participant_image ? "Yes" : "No",
      template.include_logo ? "Yes": "No",
      template.is_custom_text ? "Yes": "No",
      "#{ENV.fetch('REPORT_GENERATOR_URL')}/idev/dynamic_certificates/#{template.id}"
    ]
  end

  def communication_url communication
    [
      ENV.fetch('COMMUNICATION_DASHBOARD_URL'), "/companies/", communication.company_id,
      "/communications/details/", communication.id, "/review_details?journeyId=#{communication.journey_id}"
    ].join('')
  end

  def find_template certificate_id
    RailsVger::ReportGenerator::Idev::Certificate.api_show(certificate_id)
  rescue => e
    Rails.logger.info "Error fetching template details for id #{certificate_id}: #{e.message}"
    nil
  end

  def find_communication communication_id
    ::Timeline::Journey::ScoringCommunication.find communication_id
  end

  def custom_fields_included template
    custom_variables = template.custom_variables.pluck(:name)
    return [
      custom_variables.include?('Participant Name') ? "Yes" : "No",
      custom_variables.include?('Company Name') ? "Yes" : "No"
    ]
  end

end

Timeline::Analytics::Journies::CommunicationUsageExporter.new.perform({
  start_date: '10/04/2025',
  user_id: '66f3a6266ac049ff993c0b59'
})