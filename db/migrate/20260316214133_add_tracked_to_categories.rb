class AddTrackedToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :tracked, :boolean, default: true, null: false
  end
end
