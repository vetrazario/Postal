# Хелпер для формирования JSON ответов API
module ApiResponse
  extend ActiveSupport::Concern

  private

  def render_success(data, status: :ok)
    render json: data.merge(request_id: @request_id), status: status
  end

  def render_error(code, message, status: :unprocessable_entity)
    render json: {
      error: { code: code, message: message },
      request_id: @request_id
    }, status: status
  end

  def render_queued(email_log)
    render json: {
      status: 'queued',
      message_id: email_log.message_id,
      external_message_id: email_log.external_message_id,
      estimated_send_time: Time.current.iso8601,
      request_id: @request_id
    }, status: :accepted
  end

  def render_batch_result(batch_id, results)
    queued = results[:queued]
    failed = results[:failed]
    total = queued.size + failed.size

    status = if failed.empty?
               'queued'
             elsif queued.empty?
               'failed'
             else
               'partial'
             end

    render json: {
      status: status,
      batch_id: batch_id,
      total: total,
      queued: queued.size,
      failed: failed.size,
      results: format_batch_results(queued, failed),
      request_id: @request_id
    }, status: :accepted
  end

  def format_batch_results(queued, failed)
    queued.map { |r| r.merge(status: 'queued') } +
      failed.map { |r| r.merge(status: 'failed') }
  end
end

