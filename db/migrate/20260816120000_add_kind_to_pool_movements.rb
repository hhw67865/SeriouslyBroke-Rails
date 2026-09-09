# frozen_string_literal: true

class AddKindToPoolMovements < ActiveRecord::Migration[8.1]
  # Defaults to `transfer` (0) so every existing row and every manual reallocation stays
  # invisible to a distribution's replace-on-re-run, which deletes only `allocation` and
  # `sweep` rows. Backfilling is unnecessary: the table has no production rows, and a
  # movement written before distributions existed is a transfer by definition.
  def change
    add_column :pool_movements, :kind, :integer, null: false, default: 0
  end
end
