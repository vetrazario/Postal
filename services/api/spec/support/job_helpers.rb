# frozen_string_literal: true

module JobHelpers
  def perform_job(job_class, *args)
    job_class.new.perform(*args)
  end

  def expect_job_enqueued(job_class, &block)
    expect { block.call }.to have_enqueued_job(job_class)
  end
end
