class RemovePeriodFromBudgets < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE budgets SET amount = ROUND((amount::numeric / 12.0), 2) WHERE period = 1"
    remove_column :budgets, :period
  end

  def down
    add_column :budgets, :period, :integer, default: 0, null: false
  end
end
