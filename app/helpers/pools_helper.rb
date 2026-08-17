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
  # true and told the user nothing about the money. Since Pool#return_holdings_to_the_account an
  # envelope's balance is not destroyed with it — it returns to the account's buffer — and neither
  # is its history: its transfers re-read as the buffer's, and its categories keep counting their
  # spending against the buffer. A confirm that implies the money and the history vanish is a page
  # lying about its own outcome in the more frightening direction.
  #
  # BOTH HALVES ARE NAMED, because they are two different fears. "Where does my $400 go" is
  # answered by the balance clause; "do I lose my grocery history" is answered by the second, and
  # it is the clause the fix round added — before it, the spending genuinely did stop counting.
  #
  # A THIRD CONSEQUENCE IS DELIBERATELY NOT IN THE SENTENCE. A re-pointed category can no longer
  # carry a category-mode cap, and drops out of the Dashboard's "budgeted" band (both spelled out on
  # `Category#buffer_funded?`). It is left out because a confirm has to be read in the second before
  # a click, and a third clause about a feature the user may never have used would bury the two
  # that answer what they are actually afraid of. It is also the only reversible one — clearing the
  # category's pool, or accepting the rate suggestion this creates, puts it back — so it is a thing
  # to discover and undo rather than a thing to warn about.
  #
  # ACCOUNTS KEEP THE OLD SENTENCE, and so does an account-less pool. An account has no buffer
  # above it to absorb anything (and one holding pools is refused outright by
  # `dependent: :restrict_with_error`, which is a different message on a different screen); an
  # account-less pool is REFUSED outright the moment it has categories or unabsorbable transfers,
  # and the model says why on the page it returns to, which is a better place for a reason than a
  # confirm the user has not clicked yet.
  def pool_delete_confirmation(pool)
    return "Are you sure you want to delete this pool? This action cannot be undone." if pool.account.blank?

    "Delete #{pool.name}? Any money it is holding returns to #{pool.account.name}'s buffer, and " \
      "its history stays with it — transfers and spending both re-read as #{pool.account.name}'s. " \
      "This action cannot be undone."
  end
end
