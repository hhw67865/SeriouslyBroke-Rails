class CreateUpgrades < ActiveRecord::Migration[7.1]
  def change
    create_table :upgrades do |t|
      t.money :potential_income
      t.money :minimum_downpayment
      t.references :income_source, null: false, foreign_key: true

      t.timestamps
    end
  end
end
