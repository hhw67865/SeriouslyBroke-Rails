class AddIndexesToExistingTables < ActiveRecord::Migration[7.1]
  def change
    add_index :expenses, :date
    add_index :expenses, :frequency
    add_index :expenses, [:category_id, :date]

    add_index :paychecks, :date
    add_index :paychecks, [:income_source_id, :date]

    add_index :asset_transactions, :date
    add_index :asset_transactions, [:asset_id, :date]

    add_index :budget_statuses, :generated_at
  end
end
