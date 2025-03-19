class CreatePaychecks < ActiveRecord::Migration[7.1]
  def change
    create_table :paychecks do |t|
      t.date :date
      t.money :amount
      t.references :income_source, null: false, foreign_key: true

      t.timestamps
    end
  end
end
