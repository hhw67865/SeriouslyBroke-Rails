class CreateCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :categories do |t|
      t.string :name
      t.money :minimum_amount
      t.string :color
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
