class CreateCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :categories, id: :uuid do |t|
      t.string :name, null: false
      t.integer :category_type, null: false
      t.string :color
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :savings_pool, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
