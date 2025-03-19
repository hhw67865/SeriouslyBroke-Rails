class CreateAssetTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :asset_transactions do |t|
      t.date :date
      t.money :amount
      t.text :description
      t.belongs_to :asset, null: false, foreign_key: true

      t.timestamps
    end
  end
end
