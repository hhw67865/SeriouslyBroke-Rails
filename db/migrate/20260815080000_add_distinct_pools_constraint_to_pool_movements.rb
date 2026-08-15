# frozen_string_literal: true

class AddDistinctPoolsConstraintToPoolMovements < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :pool_movements, "from_pool_id <> to_pool_id", name: "pool_movements_distinct_pools"
  end
end
