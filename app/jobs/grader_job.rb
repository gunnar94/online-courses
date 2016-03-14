class GraderJob < ActiveJob::Base
  def perform (id)
    submission = Submission.find_by_id id

    return if submission.nil?

    submission.assessment.test_drivers.each do |t|
      worker = Grader::Worker.new
      result = TestDriverResult.new

      result.submission  = submission
      result.test_driver = t

      worker.upload_files ["#{submission.file.url}", "#{Rails.root}/spikes/#{t.name}"]
      output = worker.exec_cmd(['bash', t.name])

      result.grade   = t.points if output[:success]
      result.output  = output[:stdout].byteslice(0, Rails.configuration.grader['max_bytes'])
      result.error   = output[:stderr].byteslice(0, Rails.configuration.grader['max_bytes'])
      result.success = output[:success]

      output[:stdout] << "(Truncated to #{Rails.configuration.grader['max_bytes']} bytes)" if output[:stdout].bytesize > Rails.configuration.grader['max_bytes']
      output[:stderr] << "(Truncated to #{Rails.configuration.grader['max_bytes']} bytes)" if output[:stderr].bytesize > Rails.configuration.grader['max_bytes']

      result.save!

      files = t.test_driver_files
      path  = File.dirname(submission.file.url)

      if files.length > 0
        files.each do |f|
          tmp_path = worker.get_file(f.name)

          if tmp_path != false
            fqn = "#{path}/#{f.name}"
            FileUtils.copy tmp_path, fqn

            result_file = TestDriverResultFile.new test_driver_result: result, test_driver_file: f, path: fqn, grade: f.points
            result_file.save!
          end
        end
      end

      worker.close
    end

    submission.update graded: true
  end
end
