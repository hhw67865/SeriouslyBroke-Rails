class CreateBudgets < ActiveRecord::Migration[7.1]
  def change
    create_table :budgets, id: :uuid do |t|
      t.money :amount, null: false
      t.integer :period, null: false
      t.references :category, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
