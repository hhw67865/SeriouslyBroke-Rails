# frozen_string_literal: true

# THE PHYSICAL LEDGER, READ (two-ledger spec §2): where the money actually sits.
#
#   POT (= main checking) = income − expenses − Σ moves out + Σ moves in
#   EVERY OTHER ACCOUNT    = movements only; each mirrors its bank statement
#
# EVERY EXPENSE LEAVES CHECKING, whatever category it names and whatever that category holds
# (§2: "paying from a savings account is not a thing" — in reality you move savings → checking
# first, and recording THAT movement is the whole story). So the entry side of this ledger belongs
# entirely to the pot, and the other accounts are movement-fed with no date gate, no category
# question and no start-date rule: there is nothing to resolve, because a movement names its two
# ends outright.
#
# ONLY ACCOUNTS, ON BOTH ENDS OF EVERY MOVEMENT. The pool layer is still standing until Task 8 and
# `pool_movements` can still name an envelope, so a movement with a non-account end is skipped
# rather than counted: it is an act of intention, and this ledger only knows about location. On the
# migrated database there are none left — Task 1 converted every one of them into an `allocation` —
# but the physical partition must not depend on that being true.
#
# A SNAPSHOT, MEMOISED AT FIRST READ, on `PoolBalanceLedger`'s rule: anything that writes entries or
# movements must build a fresh ledger afterwards.
class AccountLedger
  # A BALANCE ASKED OF SOMETHING THAT IS NOT ONE OF THIS USER'S ACCOUNTS. Zero would be a wrong
  # money figure wearing the face of a right one — a brand-new account with nothing in it — and the
  # two callers this class has both iterate the user's own accounts, so anything else reaching here
  # is a caller bug rather than an empty account.
  class NotAnAccount < StandardError; end

  attr_reader :user

  def initialize(user)
    @user = user
  end

  # WHAT THE USER ACTUALLY HAS TO SPEND WITH, physically. Zero for a user with no main account at
  # all, and that is honest rather than defensive: `Category#pool_must_be_reachable` refuses a
  # category to a user who has not named one, so such a user has no categories, hence no entries,
  # hence nothing for this to be the balance of. Onboarding's first card exists to end that state.
  def pot
    main.present? ? balance_of(main) : 0.to_d
  end

  # THE BALANCE OF ONE ACCOUNT. The movement terms are every account's; the entry term is the pot's
  # alone, because that is where money enters and leaves the user's life.
  def balance_of(account)
    raise NotAnAccount, not_an_account_message(account) unless account.pool_type_account? && account.user_id == user.id

    entry_side(account) +
      totals(:movements_in).fetch(account.id, 0.to_d) -
      totals(:movements_out).fetch(account.id, 0.to_d)
  end

  # INCOME THAT LANDED IN THE POT INSIDE `range` — `PoolCalculator#income_within` re-anchored on the
  # physical side, and the distribute screen's "income this period". It is here rather than in a
  # presenter for that method's own reason: "which entries are this user's income" is one question
  # with one answer, and a presenter rebuilding the predicate would be a second one, free to
  # disagree with the balance the same figure is subtracted from.
  #
  # `.to_d` because an empty `sum(:amount)` is the Integer literal 0, and this is subtracted from a
  # BigDecimal to produce the buffer line.
  def income_within(range)
    user_entries(Entry.incomes).where(date: range).sum(:amount).to_d
  end

  private

  def main = user.default_account

  def entry_side(account)
    return 0.to_d unless main.present? && account.id == main.id

    user_entries(Entry.incomes).sum(:amount).to_d - user_entries(Entry.expenses).sum(:amount).to_d
  end

  # `fetch` with a `0.to_d` default, both halves load-bearing for `PoolBalanceLedger#terms_for`'s
  # reasons: a grouped sum has NO KEY AT ALL for an account nothing has moved into, and an Integer
  # zero leaks its type into every figure derived from it on exactly the emptiest accounts.
  def totals(term)
    @totals ||= {}
    @totals.fetch(term) { @totals[term] = compute(term) }
  end

  def compute(term)
    case term
    when :movements_in then account_movements.group(:to_pool_id).sum(:amount)
    when :movements_out then account_movements.group(:from_pool_id).sum(:amount)
    end
  end

  # `Pool.pool_types[:account]` RATHER THAN THE SYMBOL: the enum's Ruby-side casting is keyed by
  # the model's own table name, and these two conditions are on ALIASES — a symbol there is cast by
  # nothing and compared as a string against an integer column.
  #
  # BOTH ENDS JOINED AND BOTH ENDS TESTED. Filtering on the user's account ids in Ruby would be one
  # query cheaper and would freeze the account list at first read — an account created after that
  # would read as holding nothing rather than as holding what it holds. The join asks the database
  # the same question about whatever rows exist when the query runs.
  def account_movements
    PoolMovement
      .joins("INNER JOIN pools AS from_pools ON from_pools.id = pool_movements.from_pool_id")
      .joins("INNER JOIN pools AS to_pools ON to_pools.id = pool_movements.to_pool_id")
      .where(from_pools: { pool_type: Pool.pool_types[:account], user_id: user.id })
      .where(to_pools: { pool_type: Pool.pool_types[:account], user_id: user.id })
  end

  def user_entries(scope) = scope.where(categories: { user_id: user.id })

  def not_an_account_message(pool)
    return "#{pool.name} is not an account — only accounts hold money physically" unless pool.pool_type_account?

    "#{pool.name} belongs to another user"
  end
end
