class AddFrequencyToExpenses < ActiveRecord::Migration[7.1]
  def change
    add_column :expenses, :frequency, :integer

    reversible do |dir|
      dir.up do
        # Update only records with nil frequency
        Expense.where(frequency: nil).update_all(frequency: 0)
      end
    end
  end
end