class CreateExpenses < ActiveRecord::Migration[7.1]
  def change
    create_table :expenses do |t|
      t.string :name
      t.money :amount
      t.date :date
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
  end
end
