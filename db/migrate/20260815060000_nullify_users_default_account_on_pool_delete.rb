# frozen_string_literal: true

# `users.default_account_id` points at a pool, but a user's pools are destroyed
# with the user. Without ON DELETE SET NULL the still-live `users` row blocks its
# own pool's deletion, so `user.destroy` raised InvalidForeignKey. Nullify is also
# the right standalone semantic: if the pool goes away, the pointer to it clears.
class NullifyUsersDefaultAccountOnPoolDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :users, column: :default_account_id
    add_foreign_key :users, :pools, column: :default_account_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :users, column: :default_account_id
    add_foreign_key :users, :pools, column: :default_account_id
  end
end
