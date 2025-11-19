module Timeline
  module Contents
    class SyncUserExercisesStatusService < ApplicationService
      attr_reader :task
      def initialize(task_id)
        @task = Timeline::Content.find(task_id)
      end

      def call
        scope = task.user_contents
        total = scope.count
        scope.each_with_index do |user_content, index|
          Timeline::Contents::SyncUserExerciseStatusService.call(user_content)
          puts "Success: (#{index + 1} of #{total}) #{user_content.class}: #{user_content.id}"
        end
        puts "Done: #{task.class}: #{task.id}"
      end
    end
  end
end

#Timeline::Contents::SyncUserExercisesStatusService.call('684c7935334e9700093be699')
