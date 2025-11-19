class Timeline::Analytics::Journies::WeeklyReportExporter < ::BaseWorker
  def export_competency_stats workbook
    data = competency_likablity_report
    return if data.blank?
    worksheet = workbook.add_worksheet("Competency Stats")
    competency_totals = Hash.new { |h, k| h[k] = { sum_likeability: 0, count: 0 } }
    data.each do |entry|
      entry["competencies"].each do |comp|
        competency_id = comp["competency_id"]
        likeability = comp["likeability_percentage"].to_f.round(2)
        total_count = comp["total_count"] || 0 
        competency_totals[competency_id][:sum_likeability] += likeability
        if total_count > 0
          competency_totals[competency_id][:count] += 1
        end
      end
    end
    competency_averages = competency_totals.transform_values do |values|
      if values[:count] > 0
        values[:sum_likeability] / values[:count].to_f
      else
        0.0
      end
    end.transform_keys(&:to_s)
    headers = [
      "Name of the Competency", 
      "No. of Modules", 
      "Overall Completion Rate %",
      "Completion Rate Based on Logged-in Users %",
      "Likeability (%)"
    ]

    headers.each_with_index do |header, col|
      worksheet.write(0, col, header, header_format(workbook))
    end

    start_row = 1

    journey.competencies.each do |comp|
      module_count = Timeline::Content.non_archived.where(competency_id: comp.id).count
      next if module_count.zero?
      completion_percentages = journey.user_journies.non_archived.where(
        :id.in => user_journey_ids
      ).pluck(:"competency_scores.#{comp.id.to_s}").flat_map do |scores|
        scores&.map do |_, v|
          v["completion_percentage"].to_f
        end
      end.compact
      logged_in = user_profiles.select { |profile| profile[:last_logged_in_at].present? }
      if logged_in.size > 0
        logged_in_completion_percentages = journey.user_journies.non_archived.where(
          :id.in => user_journey_ids, :'user_profile_id'.in => logged_in.pluck(:id)
        ).pluck(:"competency_scores.#{comp.id.to_s}").flat_map do |scores|
          scores&.map do |_, v|
            v["completion_percentage"].to_f
          end
        end.compact
      else
        logged_in_completion_percentages = []
      end
      row = []
      if completion_percentages.size > 0
        average_completion = (completion_percentages.sum/completion_percentages.size)
        if logged_in_completion_percentages.size > 0
          average_login = (logged_in_completion_percentages.sum/logged_in_completion_percentages.size)
          row = [comp.name, module_count, "#{average_completion.round(2)}", "#{average_login.round(2)}", "#{competency_averages[comp.id.to_s].round(2)}"]
        else
          puts "logged_in_completion_percentages is empty"
          puts "Average Completion: #{average_completion}"
          puts comp.id
          puts competency_averages
          puts "Average Competency: #{competency_averages[comp.id.to_s]}"
          row = [comp.name, module_count, "#{average_completion.round(2)}", "NA", "#{competency_averages[comp.id.to_s].round(2)}"]
        end
      else
        row = [comp.name, module_count, "NA", "NA", "NA"]
      end
      worksheet.write(start_row, 0, row, cell_style(workbook))
      start_row += 1
    end
    worksheet.set_column(0, 4, 30)
  end
end

job = Timeline::Journey::ScheduledJob.find '68b155df35dd1e0002e8ad0e'

klass = job.worker_class.constantize
klass.new.perform({scheduled_job_id: job.id.to_s})