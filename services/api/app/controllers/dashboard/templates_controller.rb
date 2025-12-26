# frozen_string_literal: true

module Dashboard
  class TemplatesController < BaseController
    before_action :set_template, only: [:show, :edit, :update, :destroy]

    def index
      @templates = EmailTemplate.order(created_at: :desc)
    end

    def show
    end

    def new
      @template = EmailTemplate.new
    end

    def create
      @template = EmailTemplate.new(template_params)

      if @template.save
        redirect_to dashboard_templates_path, notice: 'Template created successfully'
      else
        render :new
      end
    end

    def edit
    end

    def update
      if @template.update(template_params)
        redirect_to dashboard_templates_path, notice: 'Template updated successfully'
      else
        render :edit
      end
    end

    def destroy
      @template.destroy
      redirect_to dashboard_templates_path, notice: 'Template deleted'
    end

    private

    def set_template
      @template = EmailTemplate.find(params[:id])
    end

    def template_params
      params.require(:email_template).permit(:name, :external_id, :html_content, :active)
    end
  end
end
