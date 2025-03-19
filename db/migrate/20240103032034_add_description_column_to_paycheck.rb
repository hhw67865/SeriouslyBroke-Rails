class AddDescriptionColumnToPaycheck < ActiveRecord::Migration[7.1]
  def change
    add_column :paychecks, :description, :string
  end
end
