class SubmissionsController < ApplicationController
  before_action :force_student, except: [:review, :grade, :download]
  before_action :force_instructor, only: [:review, :grade]

  before_action :load_submission, only: [:view, :review, :grade, :download]

  before_action :force_owner_instructor, only: [:review, :grade]

  before_action :check_configured, except: [:view, :review]
  before_action :check_ownership, only: [:view, :download]
  before_action :check_submitability, except: [:view, :review, :grade, :download]
  before_action :check_graded, only: [:review, :grade]

  def new
    @submission = Submission.new
  end

  def upload
    @submission            = Submission.new upload_submission_params
    @submission.assign_attributes({
      assessment:       @assessment,
      user:             @session.user,
      result_sourcedid: @session.launch_params.lis_result_sourcedid 
    })

    if @submission.validate
      @submission.save!

      GraderJob.perform_later @submission.id

      return redirect_to submission_results_path(@submission)
    end

    render 'new'
  end

  def view
    
  end

  def review

  end

  def grade
    submission_params                  = review_submission_params
    submission_params[:grade_approved] = true if not @submission.grade_approved

    @submission.attributes = submission_params

    if @submission.valid?
      @submission.save!
      @submission.calculate_grade

      final_grade            = FinalGrade.find_by(user: @submission.user, assessment: @assessment) || FinalGrade.new(user: @submission.user, assessment: @assessment)
      final_grade.submission = Submission.where(user: @submission.user, assessment: @assessment).order('grade DESC').limit(1)[0]
      
      final_grade.save!

      PostGradeJob.perform_later @submission.id

      return redirect_to root_path
    end

    render 'review'
  end

  def download
    send_file @submission.file.url
  end

  private
    def load_submission
      @submission = Submission.find_by_id params[:id]

      if @submission.nil?
        not_found
      end
    end

    def force_owner_instructor
      if @session.user != @submission.assessment.instructor
        @message = t('errors.launch.not_permitted')
        render 'general/error'
      end
    end

    def check_configured
      @assessment = Assessment.find_by context: @session.launch_params.context_id

      if @assessment.nil? 
        @message = t('submission.errors.not_configured')
        render 'general/error'
      end
    end

    def check_ownership
      if @session.user != @submission.user and @session.user != @submission.assessment.user
        @message = t('errors.general.no_permission')
        return render 'general/error'
      end
    end

    def check_submitability
      if not @assessment.due_date.nil? and Time.current >= @assessment.due_date
        @message = t('submission.errors.due_date_past')
        render 'general/error'
      end

      if not @assessment.submit_limit.nil? and @assessment.submit_limit > 0
        num_submissions = Submission.count assessment: @assessment, user: @session.user

        if num_submissions >= @assessment.submit_limit
          @message = t('submission.errors.too_many_submissions')
          render 'general/error'
        end
      end
    end

    def check_graded
      if not @submission.graded
        @message = t('submission.instructor.errors.not_graded')
        render 'general/error'
      end
    end

    def upload_submission_params
			params.require(:submission).permit(:file)
		end

    def review_submission_params
      params.require(:submission).permit(test_driver_results_attributes: [:id, :grade, test_driver_result_files_attributes: [:id, :grade]])
    end
end
