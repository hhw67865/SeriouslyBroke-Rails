class RemoveFrequencyFromItems < ActiveRecord::Migration[8.1]
  def change
    remove_column :items, :frequency, :integer
  end
end
