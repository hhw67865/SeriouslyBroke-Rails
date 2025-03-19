class CreateAssets < ActiveRecord::Migration[7.1]
  def change
    create_table :assets do |t|
      t.string :name
      t.belongs_to :asset_type, null: false, foreign_key: true

      t.timestamps
    end
  end
end
