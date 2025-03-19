class CreateBudgetStatuses < ActiveRecord::Migration[7.1]
  def change
    create_table :budget_statuses do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :month
      t.integer :year
      t.text :description
      t.datetime :generated_at

      t.timestamps
    end
    add_index :budget_statuses, [:user_id, :month, :year], unique: true
  end
end
