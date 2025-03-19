class AddOrderToCategories < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :order, :integer
    add_index :categories, [:user_id, :order], unique: true

    reversible do |dir|
      dir.up do
        # Initialize order for existing categories
        User.find_each do |user|
          user.categories.order(:created_at).each_with_index do |category, index|
            category.update_column(:order, index + 1)
          end
        end
      end
    end
  end
end