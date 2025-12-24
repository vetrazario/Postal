class CreateEmailTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :email_templates do |t|
      t.string :external_id, null: false, limit: 64
      t.string :name, null: false, limit: 255
      t.text :html_content, null: false
      t.text :plain_content
      t.jsonb :variables, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :email_templates, :external_id, unique: true
    add_index :email_templates, :active
  end
end

