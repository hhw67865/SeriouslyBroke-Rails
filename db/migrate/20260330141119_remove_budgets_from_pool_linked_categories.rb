# Pool-covered expense categories (linked to a savings pool) should not have budgets.
# Their spending is controlled by the pool balance, not a monthly budget.
class RemoveBudgetsFromPoolLinkedCategories < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DELETE FROM budgets
      WHERE category_id IN (
        SELECT id FROM categories WHERE savings_pool_id IS NOT NULL
      )
    SQL
  end

  def down
    # Budgets cannot be automatically restored
  end
end
