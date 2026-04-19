# frozen_string_literal: true

class AddMingModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ming_mode, :boolean, default: false, null: false
  end
end
