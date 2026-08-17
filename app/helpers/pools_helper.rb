# frozen_string_literal: true

module PoolsHelper
  # The accounts this pool could be put inside, for the form's account select.
  #
  # Through `pool.user`, never `current_user`: both `new` and the failed-create re-render
  # build the record off `current_user.pools`, so the owner is always set, and reading it
  # from the record makes the ownership scope of the collection the same object the form is
  # about — a form that could offer an account it is not allowed to name would be an IDOR
  # with a dropdown.
  #
  # `reject` rather than a `where.not`: on a new record `pool.id` is nil, and both spellings
  # of "not this one" in SQL are traps — `where.not(id: nil)` silently means "every row" and
  # `excluding(pool)` compiles to `NOT IN (NULL)`, which matches NOTHING. The comparison is
  # over at most a handful of accounts.
  def assignable_accounts_for(pool)
    pool.user.pools.accounts.order(:name).reject { |candidate| candidate == pool }
  end

  # What kind of pool this page is about, said in the subtitle. The page used to announce
  # "Savings pool details and progress" over every pool there is, and the form can now
  # create all three kinds — so a user who has just made a bank account would land on a page
  # calling it a savings pool.
  #
  # The account is named where there is one, because "which account holds this" is the exact
  # question Home sends people here to answer.
  def pool_kind_subtitle(pool)
    kind = if pool.pool_type_account? then "Bank account"
           elsif pool.pool_type_budget? then "Budget envelope"
           else
             "Savings goal"
           end
    return kind if pool.account.blank?

    "#{kind} in #{pool.account.name}"
  end

  # WHAT DELETING THIS POOL ACTUALLY DOES, said before it happens.
  #
  # The page used to warn "This action cannot be undone" over every pool there is, which was
  # true and told the user nothing about the money. Since Pool#return_movements_to_the_account
  # an envelope's balance is not destroyed with it — it returns to the account's buffer, and the
  # transfers that filled it re-read as transfers to and from that buffer. A confirm that
  # implies the money vanishes is a page lying about its own outcome in the more frightening
  # direction.
  #
  # ACCOUNTS KEEP THE OLD SENTENCE, and so does an account-less pool. An account has no buffer
  # above it to absorb anything (and one holding pools is refused outright by
  # `dependent: :restrict_with_error`, which is a different message on a different screen); an
  # orphan's money lands in whatever account is on the far end of its transfers, which is not a
  # place this page can name.
  def pool_delete_confirmation(pool)
    return "Are you sure you want to delete this pool? This action cannot be undone." if pool.account.blank?

    "Delete #{pool.name}? Any money it is holding returns to #{pool.account.name}'s buffer, " \
      "and its transfer history re-reads as money moving to and from that buffer. " \
      "This action cannot be undone."
  end
end
