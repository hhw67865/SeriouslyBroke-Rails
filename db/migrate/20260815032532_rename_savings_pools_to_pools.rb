# frozen_string_literal: true

class RenameSavingsPoolsToPools < ActiveRecord::Migration[8.1]
  def change
    rename_table :savings_pools, :pools
    rename_column :categories, :savings_pool_id, :pool_id
  end
end
