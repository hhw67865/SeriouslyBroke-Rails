class CreateItems < ActiveRecord::Migration[7.1]
  def change
    create_table :items, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.integer :frequency
      t.references :category, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
