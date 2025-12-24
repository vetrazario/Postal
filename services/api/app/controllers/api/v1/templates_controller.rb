module Api
  module V1
    class TemplatesController < Api::V1::ApplicationController
      def create
        template = EmailTemplate.new(template_params)

        if template.save
          render json: {
            id: template.id,
            external_id: template.external_id,
            name: template.name,
            created_at: template.created_at.iso8601
          }, status: :created
        else
          render json: {
            error: {
              code: 'validation_error',
              message: 'Template creation failed',
              details: template.errors.full_messages
            }
          }, status: :unprocessable_entity
        end
      end

      private

      def template_params
        params.permit(:external_id, :name, :html_content, :plain_content, variables: [])
      end
    end
  end
end

