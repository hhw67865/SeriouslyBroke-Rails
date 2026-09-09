# frozen_string_literal: true

class AddPositiveAmountConstraintToPoolMovements < ActiveRecord::Migration[8.1]
  # `amount` is a Postgres `money` column and there is no `money > integer` operator,
  # so the zero literal has to be cast; a bare `amount > 0` fails to create.
  def change
    add_check_constraint :pool_movements, "amount > 0::money", name: "pool_movements_positive_amount"
  end
end
