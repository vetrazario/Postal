# frozen_string_literal: true

class RenameModelNameToAiModel < ActiveRecord::Migration[7.1]
  def change
    rename_column :ai_settings, :model_name, :ai_model
  end
end
