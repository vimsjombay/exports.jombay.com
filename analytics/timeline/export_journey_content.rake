require 'axlsx' 

namespace :export do
  desc 'Export journey details to an Excel file'
  task :journey_details, [:journey_id] => :environment do |_, args|
    use_jombay_seller
    journey_id = args[:journey_id]
    unless journey_id
      puts 'Please provide a journey_id. Usage: rake export:journey_details[<journey_id>]'
      next
    end

    begin
      journey = Timeline::Journey.find(journey_id)
    rescue Mongoid::Errors::DocumentNotFound
      puts "Journey with ID '#{journey_id}' not found."
      next
    end

    p = Axlsx::Package.new
    wb = p.workbook

    # Sheet 1: Journey Details
    wb.add_worksheet(name: 'Journey Details') do |sheet|
      sheet.add_row ['Journey ID', 'Journey Title', 'Journey Description', 'Competencies']
      competencies_text = journey.competencies.map { |c| "#{c.name}: #{c.description}" }.join("\n")
      sheet.add_row [journey.id.to_s, journey.name, journey.description, competencies_text]
    end

    # Sheet 2: Contents
    wb.add_worksheet(name: 'Contents') do |sheet|
      sheet.add_row ['Content ID', 'Content Title', 'Content Type', 'Content Description', 'Sequence/Order']
      Timeline::Content.where(:milestone_id.in => journey.milestone_ids).each_with_index do |content, index|
        sheet.add_row [content.id.to_s, content.title, content.content_type, content.description, index + 1]
      end
    end

    # Create a hash to map content_id to content_title for quick lookup
    content_titles = Timeline::Content.where(:milestone_id.in => journey.milestone_ids).each_with_object({}) do |content, hash|
      hash[content.id.to_s] = content.title
    end

    # Sheet 3: Questions and Sheet 4: Question Options
    wb.add_worksheet(name: 'Questions') do |question_sheet|
      wb.add_worksheet(name: 'Question Options') do |option_sheet|
        question_sheet.add_row ['Question ID', 'Content ID', 'Content Title', 'Question Text', 'Question Type']
        option_sheet.add_row ['Option ID', 'Question ID', 'Question Text', 'Option Text', 'Is Correct']

        Timeline::Content.where(:milestone_id.in => journey.milestone_ids).each do |content|
          content.questions.each do |question|
            content_title = content_titles[content.id.to_s]
            question_sheet.add_row [question.id.to_s, content.id.to_s, content_title, question.body, question.render_type]
            question.options.each do |option|
              option_sheet.add_row [option.id.to_s, question.id.to_s, question.body, option.body, option.is_correct]
            end
          end
        end
      end
    end

    # Sheet 5: Flash Cards
    wb.add_worksheet(name: 'Flash Cards') do |sheet|
      sheet.add_row ['Flash Card ID', 'Content ID', 'Content Title', 'Body']
      Timeline::Content.where(:milestone_id.in => journey.milestone_ids).each do |content|
        content.flash_cards.each do |flash_card|
          sheet.add_row [flash_card.id.to_s, content.id.to_s, content.title, flash_card.body]
        end
      end
    end

    # Sheet 6: Manager Questions and Sheet 7: Manager Question Options
    wb.add_worksheet(name: 'Manager Questions') do |mq_sheet|
      wb.add_worksheet(name: 'Manager Question Options') do |mq_option_sheet|
        mq_sheet.add_row ['Manager Question ID', 'Content ID', 'Content Title', 'Question Text']
        mq_option_sheet.add_row ['Option ID', 'Manager Question ID', 'Manager Question Text', 'Option Text', 'Is Correct']

        Timeline::Feedback.where(:milestone_id.in => journey.milestone_ids).each do |content|
          content.manager_questions.each do |question|
            content_title = content_titles[content.id.to_s]
            mq_sheet.add_row [question.id.to_s, content.id.to_s, content_title, question.body]
            question.options.each do |option|
              mq_option_sheet.add_row [option.id.to_s, question.id.to_s, question.body, option.body, option.is_correct]
            end
          end
        end
      end
    end

    # Sheet 8: Form Fields
    wb.add_worksheet(name: 'Form Fields') do |sheet|
      sheet.add_row ['Form Field ID', 'Content ID', 'Content Title', 'Field Label', 'Field Type', 'Placeholder', 'Options']
      Timeline::Form.where(:milestone_id.in => journey.milestone_ids).each do |form|
        form.form_fields.each do |field|
          sheet.add_row [field.id.to_s, form.id.to_s, form.title, field.label, field.field_type, field.placeholder, field.options.join(' | ')]
        end
      end
    end

    file_path = Rails.root.join('tmp', "journey_export_#{journey_id}_#{Time.now.to_i}.xlsx")
    p.serialize(file_path.to_s)
    puts "Successfully exported journey details to #{file_path}"

    puts "Sending email with the exported file..."
    user = User.first # Replace with actual user retrieval logic
    ExportMailer.with(user: user, file_path: file_path).journey_export.deliver_now
    puts "Email sent."
  end
end
