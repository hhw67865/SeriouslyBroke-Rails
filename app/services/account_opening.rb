# frozen_string_literal: true

# ** WHAT AN ACCOUNT HOLDS, SAID ONCE AND CORRECTABLE FOREVER (account-openings spec §§2 and 4). **
#
# Henry, 2026-09-06: "Not many people are going to know how much TOTAL money they have and then
# divide it all off. Instead they just want to put in what their accounts are currently worth. The
# fact you have to get the ordering exactly right is bad user experience."
#
# So this object takes ONE account and ONE figure — what the bank shows for it right now — and writes
# the record that makes the app agree:
#
#   MAIN            one entry of `B` in the opening category. There is no movement: main IS where
#                   money enters this user's life, so there is nowhere for it to have come from.
#   ANY OTHER       that entry PLUS one transfer of `B` between main and the account, same day. The
#                   entry brings the money into the user's world; the transfer puts it where they
#                   said it is. Main is left exactly where it was, which is what makes every save
#                   SELF-CONTAINED and the ORDER of the saves irrelevant.
#
# ** A CORRECTION REWRITES THE RECORD IN PLACE (§1: "Corrections should be done on the same initial
# entry. Actual movements appear as adjustments based on time"). ** Never a second entry: the amount
# is recomputed as `typed − (what has flowed through the account since)` and the date stays the
# opening day. One formula covers both cases, because "what has flowed through since" is just this
# account's balance with its own opening record taken back out:
#
#     amount = typed − balance_of(account) + (what the existing opening record contributes to it)
#
# For main that expands to §2's `typed − (income − expenses since, excluding the opening entry) +
# Σ movements out − Σ movements in`; for any other account, to `typed − Σ (other movements in − out)`.
# There is ONE spelling of balance arithmetic in this app (`AccountLedger`) and this reads it rather
# than re-deriving a SUM of its own.
#
# ** IT IS THE ONLY WRITER of opening entries and opening movements (§4). ** `AccountFundingsController`
# (onboarding step 2) and `OpeningBalancesController` (step 3) are deleted; the opening-day rule that
# lived in the latter is `#opening_day` below, spelled once.
#
# ** WHAT IS NOT HERE: `AccountLedger` and the invariant. ** `pot + Σ other accounts == income −
# expenses` is a fact about entries and movements together, and every write below moves both halves
# or neither. `spec/services/account_opening_spec.rb` asserts it by raw SQL on both sides of every
# save it makes.
class AccountOpening
  include ActiveModel::Model

  # `typed` IS WHAT THE USER ACTUALLY PUT IN THE FIELD, kept beside the parsed figure so a refused
  # save can re-render the row with their own characters in it — including the ones that failed to
  # parse, which is exactly the case `balance` has nothing to show for.
  attr_reader :user, :account, :balance, :typed

  # `balance` arrives as whatever the wire carried — a decimal string from the form, a BigDecimal
  # from a caller in Ruby, nil from a blank field. `BigDecimal(…, exception: false)` answers nil for
  # anything unparsable rather than raising, and `.round(2)` lands it on the only unit this app has:
  # a figure like `0.001` would otherwise survive the zero check below and then be rounded to zero by
  # `entries.amount`'s own scale, failing `greater_than: 0` inside the transaction as an unhandled
  # RecordInvalid. Rounding here means the comparison and the write agree.
  def initialize(user, account, balance:)
    @user = user
    @account = account
    @typed = balance
    @balance = BigDecimal(balance.to_s, exception: false)&.round(2)
  end

  validate :balance_is_a_figure
  validate :balance_is_not_negative_off_main
  validate :a_main_account_exists

  # TRUE OR FALSE, and `#errors` says why — the shape every caller on this screen already speaks
  # (`BankAccountsController` and `AccountOpeningsController` both re-render Home at 422 with the
  # rejected object as the form's own).
  #
  # A STRANGER'S ACCOUNT RAISES rather than answering false: the controllers scope through
  # `current_user.pools.accounts`, so a foreign account reaching here is a caller bug, and it is the
  # same refusal `AccountLedger` makes about the same question rather than a second spelling of it.
  # rubocop:disable Naming/PredicateMethod -- `#save` answering true/false with `#errors` beside it is
  # the ActiveRecord shape every caller of this object already speaks; `save?` would be a third
  # convention on a screen where `Pool#save` and `Entry#save` are the other two.
  def save
    raise AccountLedger::NotAnAccount, "#{account.name} belongs to another user" unless account.user_id == user.id
    return false if invalid?

    # LOCKED, the idiom `Category.apply_fill_order` and the deleted funding controller both used for
    # the same reason: two submits for one account — a double-click, a resubmit before the redirect
    # lands — must not both read "the opening is $500" and both write. The second request's `lock!`
    # blocks until the first commits, so the second recomputes against what the first actually wrote.
    Pool.transaction do
      account.lock!
      day = account.opened_on || opening_day
      write(recomputed_amount, day)
      account.update!(opened_on: day)
    end
    true
  end
  # rubocop:enable Naming/PredicateMethod

  private

  # ** THE OPENING DAY, AND THE ONE SPELLING OF IT ** (hoisted from the deleted
  # `OpeningBalancesController#opening_day`, Henry's ruling of 2026-08-20 from real use): the day
  # before the user's earliest entry, so the money is inside no period anybody will ever read. It is
  # asked ONCE per account — `pools.opened_on` keeps the answer — because the answer MOVES as the
  # user records older history, and §2 says the record's date stays the opening day.
  #
  # ** OPENING ENTRIES ARE EXCLUDED FROM THE SEARCH, and that arm is load-bearing. ** They are not
  # the user's history; they are dated the opening day itself. Counting them would open each new
  # account a day before the last one, walking the whole set backwards through the calendar one
  # account at a time.
  def opening_day
    earliest = user.entries.where(opening_account_id: nil).minimum(:date)

    earliest ? earliest.to_date - 1 : user.today
  end

  # `typed − what has flowed through the account since the opening day`, which is the same thing as
  # `typed − (this account's balance with its own opening record removed)`. Read through
  # `AccountLedger`, which is the app's one reader of a balance; the second term is what THIS
  # account's own record contributes to that figure, and nothing else needs to be known.
  def recomputed_amount = (balance - AccountLedger.new(user).balance_of(account) + existing_contribution).round(2)

  # WHAT THE EXISTING RECORD IS WORTH TO *THIS* ACCOUNT'S BALANCE — asked of the row that actually
  # moves it, which is a different row for main than for anyone else:
  #
  #   main   the ENTRY (income adds to the pot, a shortfall takes off it); no movement exists.
  #   other  the MOVEMENT (in adds, out takes off); the entry moves MAIN, and cancels against the
  #          movement's other end, so main is untouched by another account's opening.
  def existing_contribution
    entry = existing_entry
    return 0.to_d if entry.blank?
    return signed(entry.amount, entry.item.category.income?) if main?

    movement = opening_movement(entry)
    return 0.to_d if movement.blank?

    signed(movement.amount, movement.to_pool_id == account.id)
  end

  def signed(amount, positive) = positive ? amount : -amount

  # ONE ROW BY CONSTRUCTION AND BY THE DATABASE: `entries.opening_account_id` carries a unique index,
  # so "which entry is this account's opening" has one answer or none.
  def existing_entry = Entry.find_by(opening_account_id: account.id)

  # ** THE OPENING MOVEMENT IS THE ONE THE OPENING ENTRY CAUSED, ** found by
  # `account_movements.source_entry_id` — the link this app already uses to pair an income entry with
  # the transfer that mirrors it (`Entry#route_income_to!`, `Entry#routed_account`). A structural
  # match ("the transfer dated the opening day from main to this account") was the alternative and it
  # is wrong on a shape users produce: a transfer the user really made on the same day matches it
  # too. A user's own transfer names no source entry, so this one cannot be confused with it.
  # `sole` AND NOT `first` (fix round — LOW-1), which makes the one-row law load-bearing rather than
  # assumed: `#write_movement` clears before it writes, so an opening entry has AT MOST one transfer
  # by construction, and `first` on an unordered query would quietly pick one of two if that ever
  # stopped being true — handing the correction a figure half the ledger disagreed with. The empty
  # case is answered before it is asked, because "main's opening has no movement" is the ordinary
  # answer rather than a violation.
  def opening_movement(entry)
    movements = entry.account_movements.kind_transfer.to_a
    return if movements.empty?

    movements.sole
  end

  # ** ONE ROW, ALWAYS, INCLUDING FOR ZERO (fix round — MED-4). ** It used to DESTROY the entry when
  # the recomputed amount came out at zero and lean on `pools.opened_on` to remember that the account
  # had answered. The gate is the entry's own existence now — so that deleting it from the Entries
  # screen puts the question back on the account's card — and a destroyed row would have made "this
  # account holds nothing" and "this account has never been asked" the same state. Two ordinary
  # households live in that state: a fresh savings account, and a checking account whose balance the
  # app already tracks to the cent. `Entry`'s own validation carves zero out for exactly this row.
  def write(amount, day)
    entry = existing_entry || Entry.new(opening_account: account)
    entry.update!(item: item_for(amount), amount: amount.abs, date: day, description: "#{account.name} opening balance")
    write_movement(entry, amount, day)
  end

  # ** THE MOVEMENT IS WRITTEN HERE RATHER THAN BY `Entry#route_income_to!`, and the reason is the
  # direction. ** That method writes main → account and only that, which is right for an opening the
  # user has money in; an account stated BELOW what the app has moved into it opens negative, and the
  # transfer that says so runs account → main. Everything else is the same idiom, including clearing
  # first so a correction replaces rather than accumulates.
  # A ZERO OPENING CARRIES NO MOVEMENT — there is nothing to move, and `account_movements` has its
  # own `amount > 0` CHECK at the database, so writing one would be refused rather than pointless.
  def write_movement(entry, amount, day)
    entry.account_movements.kind_transfer.destroy_all
    return if main? || amount.zero?

    from, to = amount.positive? ? [main, account] : [account, main]
    entry.account_movements.create!(from_pool: from, to_pool: to, amount: amount.abs, date: day, kind: :transfer)
  end

  # THE CATEGORY THE ENTRY LANDS IN, BY SIGN (`Category::OPENING_NAMES` states the pair and why there
  # are two). Auto-created on demand, which is the deleted `OpeningBalancesController#write_correction`'s
  # own code moved here rather than rewritten:
  #
  #   `tracked: false` — this entry is bookkeeping, not a fact about a period's income or spending.
  #   `Dashboard::IncomePresenter#total_tracked_income` and its expense twin both sum by that flag,
  #   and years of history the app never saw would otherwise land in THIS period's figures.
  #
  # `find_or_create_by!` on the CASE-INSENSITIVE scope rather than on `name:`, so a user who already
  # has a category spelled "opening balance" is found rather than collided with — `Category` validates
  # its name unique case-insensitively, and a bare create would turn a saved balance into a crash.
  # ZERO IS AN `Opening Balance`, NOT A SHORTFALL. Nothing is short: the account holds exactly what
  # the app says it holds, and filing that under an expense named "Opening Shortfall" would put a
  # sentence in the user's history that is not true of them.
  def category_for(amount)
    income = !amount.negative?
    name = income ? Category::OPENING_BALANCE_NAME : Category::OPENING_SHORTFALL_NAME

    user.categories.opening.find { |category| category.name.casecmp?(name) } ||
      user.categories.create!(name: name, category_type: income ? :income : :expense, tracked: false)
  end

  def item_for(amount) = category_for(amount).items.find_or_create_by!(name: "Initial balance")

  def main = user.default_account

  def main? = main.present? && account.id == main.id

  def balance_is_a_figure
    errors.add(:balance, "must be a number") if balance.nil?
  end

  # A MIRROR CANNOT BE OVERDRAWN BY CONSTRUCTION (§4) — a non-main account holds what has been moved
  # into it — while an overdrawn checking account is a fact, so main takes a negative figure. This is
  # about the TYPED balance; a correction whose computed amount comes out negative is a different
  # statement (untracked history left the account holding less than its transfers say) and is legal.
  def balance_is_not_negative_off_main
    return if balance.nil? || !balance.negative? || main?

    errors.add(:balance, "can't be negative for an account that isn't your main one")
  end

  # NO MAIN ACCOUNT MEANS NO SOURCE for the transfer a non-main opening needs, and inventing one
  # would move money the user never had. Main itself is still openable, which is the door out of the
  # state (`users.default_account_id` nullifies when the main account is deleted).
  def a_main_account_exists
    return if main?

    errors.add(:base, "Add a main account before saying what this one holds") if main.blank?
  end
end
