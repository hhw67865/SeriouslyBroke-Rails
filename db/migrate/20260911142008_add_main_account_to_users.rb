# frozen_string_literal: true

class AddMainAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :main_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
  end
end
