class CreateSavingsPools < ActiveRecord::Migration[7.1]
  def change
    create_table :savings_pools, id: :uuid do |t|
      t.string :name, null: false
      t.money :target_amount
      t.references :user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
