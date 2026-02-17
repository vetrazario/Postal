class AddWarmupStartDateToSystemConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :system_configs, :warmup_start_date, :string
  end
end
