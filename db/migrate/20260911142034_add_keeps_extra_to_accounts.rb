# frozen_string_literal: true

class AddKeepsExtraToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :keeps_extra, :boolean, null: false, default: true
  end
end
