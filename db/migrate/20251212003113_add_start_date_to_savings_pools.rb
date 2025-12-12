class AddStartDateToSavingsPools < ActiveRecord::Migration[7.1]
  def change
    add_column :savings_pools, :start_date, :date
  end
end
