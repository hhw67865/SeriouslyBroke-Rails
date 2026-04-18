class AddProratedToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :prorated, :boolean, default: false, null: false
  end
end
