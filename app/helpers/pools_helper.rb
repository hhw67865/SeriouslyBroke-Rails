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
end
