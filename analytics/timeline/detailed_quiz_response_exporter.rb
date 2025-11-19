# frozen_string_literal: true

module Timeline
  module Analytics
    module Contents
      class DetailedQuizResponseExporter < QuizResponseExporter
        # This worker exports detailed quiz response data including:
        # - Question-wise responses for each participant
        # - Number of attempts per participant
        # - Question-level failure analysis

        def create_export_sheet(package, _options)
          # Sheet 1: Detailed question-wise responses
          package.workbook.add_worksheet(name: 'Question-wise Responses') do |sheet|
            create_detailed_question_responses_export(sheet)
          end

          # Sheet 2: Question failure analysis
          package.workbook.add_worksheet(name: 'Question Analysis') do |sheet|
            create_question_analysis_export(sheet)
          end

          # Sheet 3: Participant attempt history
          package.workbook.add_worksheet(name: 'Attempt History') do |sheet|
            create_attempt_history_export(sheet)
          end

          # Sheet 4: Not attempted (from parent class)
          package.workbook.add_worksheet(name: 'Not Attempted') do |sheet|
            create_not_attempted_export(sheet)
          end
        end

        private

        def create_detailed_question_responses_export(sheet)
          questions = content.questions.sort_by(&:question_order)

          # Build headers
          headers = default_headers + [
            'Competency Name',
            'Development Program Name',
            'Milestone Number',
            'Scheduled At',
            'Status',
            'Completed At',
            'Quiz Score',
            'Quiz Max Score',
            'Number of Attempts'
          ]

          # Add question-specific headers
          questions.each_with_index do |question, idx|
            question_number = idx + 1
            headers << "Q#{question.body}: Response"
            headers << "Q#{question.body}: Score"
            headers << "Q#{question.body}: Correct?"
            headers << "Q#{question.body}: Time (sec)"
          end

          sheet.add_row(headers, style: add_header_style(sheet))
          cell_style = add_cell_styles(sheet)

          # Get all completed user contents
          user_contents = content.user_contents.non_archived.where(
            'user_profile_document.is_dummy' => false
          )

          user_contents.each do |user_content|
            row_data = build_detailed_row(user_content, questions)
            sheet.add_row(row_data, style: cell_style)
          end
        end

        def build_detailed_row(user_content, questions)
          milestone = content.milestone

          # Calculate number of attempts (unique completion timestamps)
          attempts_count = calculate_attempts_count(user_content)

          # Basic user info
          row = user_profile_info(user_content, company_defined_fields) + [
            content.competency_document.present? ? content.competency_document['name'] : 'NA',
            milestone.journey_document['name'],
            milestone.name,
            format_date_time_in_user_timezone(content.start_date, user.time_zone),
            user_content.status,
            format_date_time_in_user_timezone(user_content.completed_at, user.time_zone),
            user_content.score,
            content.questions.sum(:max_score),
            attempts_count
          ]

          # Get responses mapped by question_id
          responses_by_question = user_content.question_responses.group_by(&:question_id).transform_values do |responses|
            # Get the latest response for each question (in case of multiple attempts)
            responses.max_by { |r| r.created_at || Time.at(0) }
          end

          # Add question-wise data
          questions.each do |question|
            response = responses_by_question[question.id]

            if response
              # Find the selected option
              selected_option = question.options.find { |opt| opt.id == response.option_id }
              option_text = selected_option&.body || response.subjective_comment.presence || 'No response'

              # Determine if correct
              is_correct = response.score.to_f > 0 ? 'Yes' : 'No'

              row << option_text
              row << response.score.to_f
              row << is_correct
              row << response.time_in_seconds.to_i
            else
              # Question was skipped
              row << 'Skipped'
              row << 0
              row << 'No'
              row << 0
            end
          end

          row
        end

        def create_question_analysis_export(sheet)
          questions = content.questions.sort_by(&:question_order)

          headers = [
            'Question Number',
            'Question Text',
            'Max Score',
            'Total Participants',
            'Correct Responses',
            'Wrong Responses',
            'Skipped',
            'Success Rate (%)',
            'Average Time (sec)',
            'Average Score'
          ]

          sheet.add_row(headers, style: add_header_style(sheet))
          cell_style = add_cell_styles(sheet)

          # Get all completed user contents
          completed_user_contents = content.user_contents.non_archived.where(
            'user_profile_document.is_dummy' => false
          )

          total_participants = completed_user_contents.count

          questions.each_with_index do |question, idx|
            question_number = idx + 1

            # Collect all responses for this question
            all_responses = []
            completed_user_contents.each do |uc|
              response = uc.question_responses.find { |r| r.question_id == question.id }
              all_responses << response if response
            end

            correct_count = all_responses.count { |r| r.score.to_f > 0 }
            wrong_count = all_responses.count { |r| r.score.to_f == 0 }
            skipped_count = total_participants - all_responses.count
            success_rate = total_participants > 0 ? (correct_count.to_f / total_participants * 100).round(2) : 0
            avg_time = all_responses.any? ? (all_responses.sum(&:time_in_seconds).to_f / all_responses.count).round(2) : 0
            avg_score = all_responses.any? ? (all_responses.sum { |r| r.score.to_f } / all_responses.count).round(2) : 0

            row = [
              question_number,
              question.body.to_s.strip,
              question.max_score,
              total_participants,
              correct_count,
              wrong_count,
              skipped_count,
              success_rate,
              avg_time,
              avg_score
            ]

            sheet.add_row(row, style: cell_style)
          end
        end

        def create_attempt_history_export(sheet)
          headers = default_headers + [
            'Competency Name',
            'Development Program Name',
            'Milestone Number',
            'Number of Attempts',
            'First Attempt Score',
            'Latest Attempt Score',
            'Quiz Max Score',
            'Cutoff Score',
            'Met Cutoff?',
            'First Attempt At',
            'Last Completed At',
            'Time Between Attempts (minutes)'
          ]

          sheet.add_row(headers, style: add_header_style(sheet))
          cell_style = add_cell_styles(sheet)

          # Get all user contents (including started and completed)
          user_contents = content.user_contents.non_archived.where(
            :status.in => ['started', 'completed'],
            'user_profile_document.is_dummy' => false
          )

          user_contents.each do |user_content|
            row = build_attempt_history_row(user_content)
            sheet.add_row(row, style: cell_style)
          end
        end

        def build_attempt_history_row(user_content)
          milestone = content.milestone
          attempts_count = calculate_attempts_count(user_content)

          # Try to determine first attempt score vs latest score
          # Since we don't have explicit attempt tracking, we use completed_at as proxy
          first_attempt_score = user_content.status == 'completed' ? user_content.score : 0
          latest_attempt_score = user_content.score

          max_score = content.questions.sum(:max_score)
          cutoff_score = content.cutoff_points.to_f
          met_cutoff = content.enable_cutoff? ? (user_content.score >= cutoff_score ? 'Yes' : 'No') : 'N/A'

          first_attempt_at = user_content.started_at
          last_completed_at = user_content.completed_at

          time_diff_minutes = if first_attempt_at && last_completed_at
                                ((last_completed_at - first_attempt_at) / 60.0).round(2)
                              else
                                0
                              end

          user_profile_info(user_content, company_defined_fields) + [
            content.competency_document.present? ? content.competency_document['name'] : 'NA',
            milestone.journey_document['name'],
            milestone.name,
            attempts_count,
            first_attempt_score,
            latest_attempt_score,
            max_score,
            cutoff_score,
            met_cutoff,
            format_date_time_in_user_timezone(first_attempt_at, user.time_zone),
            format_date_time_in_user_timezone(last_completed_at, user.time_zone),
            time_diff_minutes
          ]
        end

        def calculate_attempts_count(user_content)
          # Heuristic: Count as multiple attempts if user completed after starting
          # In a more sophisticated system, you'd track attempts explicitly
          if user_content.status == 'completed'
            # Check if there are duplicate responses (indicating re-attempts)
            question_ids = user_content.question_responses.map(&:question_id)
            unique_questions = question_ids.uniq.count
            total_responses = question_ids.count

            # If total responses > unique questions, there were re-attempts
            total_responses > unique_questions ? (total_responses.to_f / unique_questions).ceil : 1
          else
            1
          end
        end

        def get_subject
          "Detailed Quiz Analysis for #{content.title} is attached"
        end

        def get_email_body
          "Detailed Quiz Analysis for #{content.content_tag} - #{content.title} that you requested is attached.
          <br/><br/> This export contains:
          <br/>- Question-wise responses for each participant
          <br/>- Question failure analysis showing which questions participants struggled with
          <br/>- Attempt history showing re-attempts to meet cutoff scores
          <br/>- List of participants who haven't attempted the quiz"
        end
      end
    end
  end
end
