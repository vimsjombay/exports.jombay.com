# frozen_string_literal: true

# Perfios Quiz Exporter
#
# Exports quiz responses showing which option each participant selected
# and whether the selected option was correct or incorrect
#
# Usage:
#   1. Edit the setup method below with your company_id, journey_id, and email
#   2. Run from Rails console:
#      PerfiosQuizExporter.new.perform
#
class PerfiosQuizExporter < BaseWorker
  attr_accessor :company, :journey, :user

  def perform(options = {})
    setup(options)

    puts "\n" + "=" * 80
    puts "PERFIOS QUIZ EXPORT"
    puts "=" * 80
    puts "Company ID: #{company.id}"
    puts "Company Name: #{company.name}"
    puts "Journey ID: #{journey.id}"
    puts "Journey Name: #{journey.name}"
    puts "=" * 80 + "\n"

    create_package
  rescue StandardError => e
    puts "\n✗ CRITICAL ERROR: #{e.class}: #{e.message}"
    puts "Stack trace:\n#{e.backtrace.first(10).join("\n")}"
    raise e
  end

  private

  def setup(options)
    RequestStore.store[:user_id] = options[:user_id]
    @user = RailsVger::AuthApi::User.api_find(options[:user_id]) if options[:user_id]
    @company = RailsVger::AuthApi::Company.api_find(options[:company_id])
    @journey = Timeline::Journey.find(options[:journey_id])
  end

  def create_package
    file_name = "Perfios_Quiz_Export_#{journey.name.sanitize}_#{Time.now.to_fs(:underscored)}.xlsx"
    # Save to public directory (accessible via web)
    file_path = File.join(Dir.pwd, 'public', 'exports', file_name)

    # Create exports directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(file_path))

    Axlsx::Package.new do |package|
      # Get all milestones in this journey
      milestones = journey.milestones

      # Find all quiz contents across all milestones
      quiz_contents = Timeline::Content.where(
        :milestone_id.in => milestones.pluck(:id),
        content_type: 'quiz'
      ).non_archived

      if quiz_contents.empty?
        puts "No quiz content found for journey: #{journey.name}"
        return nil
      end

      puts "Found #{quiz_contents.count} quiz(zes) in journey: #{journey.name}\n\n"

      # Create a sheet for each quiz
      quiz_contents.each do |content|
        puts "Processing: #{content.title}"
        package.workbook.add_worksheet(name: sanitize_sheet_name(content.title)) do |sheet|
          rows_added = create_quiz_export_sheet(sheet, content)
        end
      end

      package.serialize(file_path)
    end

    # Verify file was created
    if File.exist?(file_path)
      file_size = File.size(file_path)
      puts "\n✓ Export completed successfully!"
      puts "=" * 80
      puts "FILE SAVED AT: #{file_path}"
      puts "FILE SIZE: #{file_size} bytes (#{(file_size / 1024.0).round(2)} KB)"
      puts "=" * 80
    else
      puts "\n✗ ERROR: File was not created at #{file_path}"
      puts "Checking if directory exists: #{File.directory?(File.dirname(file_path))}"
      puts "Directory permissions: #{File.stat(File.dirname(file_path)).mode.to_s(8)}" rescue "Cannot check"
      return nil
    end

    if user.present?
      puts "\nSending email to: test.user@jombay.com..."
      send_export_email(file_name, file_path)
      puts "Email sent successfully!"
    end

    puts "\n" + "=" * 80
    puts "EXPORT COMPLETE"
    puts "=" * 80

    file_path
  end

  def create_quiz_export_sheet(sheet, content)
    # Get questions sorted by question_order
    questions = content.questions.sort_by(&:question_order)

    # Build header row
    header = build_header_row(questions)

    # Add header with bold style
    header_style = sheet.styles.add_style(b: true)
    sheet.add_row(header, style: header_style)

    # Get completed user contents (excluding dummy users)
    user_contents = content.user_contents.non_archived.where(
      status: 'completed',
      'user_profile_document.is_dummy' => false
    )

    completed_count = user_contents.count
    puts "  - Found #{completed_count} completed responses"

    # Export each user's responses
    rows_added = 0
    user_contents.each do |user_content|
      next if user_content.question_responses.empty?

      row = build_user_row(user_content, content, questions)
      sheet.add_row(row)
      rows_added += 1
    end

    rows_added
  end

  def build_header_row(questions)
    header = [
      'Name',
      'Username',
      'Email',
      'Completed At',
      'Quiz Score',
      'Quiz Max Score'
    ]

    # Add columns for each question
    questions.each_with_index do |question, index|
      question_number = index + 1
      header += [
        "Q#{question_number}: Question",
        "Q#{question_number}: Selected Option",
        "Q#{question_number}: Is Correct?"
      ]
    end

    header
  end

  def build_user_row(user_content, content, questions)
    # Calculate max score
    max_score = questions.sum(&:max_score)

    # Basic user info
    row = [
      user_content.user_profile_document['user_document']['name'],
      user_content.user_profile_document['user_document']['username'],
      user_content.user_profile_document['user_document']['email'],
      user_content.completed_at ? user_content.completed_at.strftime('%Y-%m-%d %H:%M:%S') : '-',
      user_content.score.to_f,
      max_score
    ]

    # Get responses mapped by question_id for efficient lookup
    responses_by_question = user_content.question_responses.group_by(&:question_id).transform_values(&:first)

    # Add response data for each question
    questions.each do |question|
      response = responses_by_question[question.id]

      if response.present? && response.option_id.present?
        # Find the selected option
        selected_option = question.options.find { |opt| opt.id == response.option_id }

        if selected_option
          # Determine if the selected option is correct
          is_correct = selected_option.is_correct ? 'Correct' : 'Incorrect'

          row += [
            question.body.to_s.strip,
            selected_option.body.to_s.strip,
            is_correct
          ]
        else
          # Option not found
          row += [
            question.body.to_s.strip,
            'Option Not Found',
            'Incorrect'
          ]
        end
      elsif response.present? && response.subjective_comment.present?
        # Subjective response
        row += [
          question.body.to_s.strip,
          response.subjective_comment.to_s.strip,
          response.score.to_f > 0 ? 'Correct' : 'Incorrect'
        ]
      else
        # No response for this question
        row += [
          question.body.to_s.strip,
          'Not Answered',
          'Incorrect'
        ]
      end
    end

    row
  end

  def send_export_email(file_name, file_path)
    SystemMailer.report_messages(
      {
        to: user.try(:email) || 'test.user@jombay.com',
        bcc: 'engineering@jombay.com'
      },
      "Perfios Quiz Export - #{journey.name}",
      {
        report: {
          journey_id: journey.id,
          journey_name: journey.name,
          company: company.name,
          message: "Please find attached the quiz export for #{journey.name}. This report shows each participant's selected options and whether they were correct or incorrect.",
          attachments: {
            files: [
              {
                name: file_name,
                path: file_path
              }
            ]
          }
        }
      }
    ).deliver!
  end

  def sanitize_sheet_name(name)
    # Excel sheet names have max 31 characters and cannot contain: \ / ? * [ ] : '
    name.gsub(/[\[\]\\\/\?\*:']/, '').strip.truncate(31, omission: '...')
  end
end

# ============================================================================
# EDIT THESE VALUES BEFORE RUNNING
# ============================================================================

PerfiosQuizExporter.new.perform({
  company_id: '6901e9b76f6363aa8a28cf7b', journey_id: '69082f1be1d7a900026374e4' , user_id: '66580e9905d2660008129935'
})