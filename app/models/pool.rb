# frozen_string_literal: true

# ONE OF THE USER'S REAL BANK ACCOUNTS, and after the drop (two-ledger spec §5) that is the whole
# of what a Pool is. The table keeps its name — §8 rules the rename cosmetic and out of scope — but
# every branch that made a pool anything else is gone with the column that expressed it:
#
#   * `pool_type` has one member. `pools_are_accounts` says so at the database, past the model.
#   * `account_id` and `child_pools` are gone: nesting was how an envelope said which account it
#     sat in, and a category holds its own money now (§2). With them go the destroy-time
#     re-pointing machinery, `REFUSALS`, and `User#destroy_child_pools_first`.
#   * `start_date`, `target_amount` and `priority` are gone. They were the envelope's three
#     columns; the goal that wanted them is a `Category` carrying `funded_since`, `target_amount`
#     and `priority` of its own. `target_amount`'s "buffer marker" was a parked question and the
#     ruling is no.
#   * `NOUNS` is gone with the three types it named. An account is a "buffer" wherever a screen
#     needs the word, and `EntryImpactPresenter#noun` names the two shapes a CATEGORY has.
#   * `#calculator`, `#status`, `#total` and `#timeline` are gone with `PoolCalculator`,
#     `PoolStatus`, `PoolProjection` and `PoolBalanceLedger`. What an account holds is
#     `AccountLedger`'s answer and #balance below is the one door onto it.
#
# WHAT AN ACCOUNT STILL IS: a name, a user, and two directions of movement. Money enters and leaves
# the user's life through `Entry`; it moves between their own accounts through `AccountMovement`.
class Pool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true

  has_many :movements_in,
           class_name: "AccountMovement",
           foreign_key: :to_pool_id,
           dependent: :destroy,
           inverse_of: :to_pool
  has_many :movements_out,
           class_name: "AccountMovement",
           foreign_key: :from_pool_id,
           dependent: :destroy,
           inverse_of: :from_pool

  # ONE MEMBER, AND THE COLUMN SURVIVES THE TYPE IT ONCE DISCRIMINATED. `pool_type_account?` is
  # still asked in a dozen places — `User#default_account_is_own_account`, `AccountLedger#balance_
  # of`, every `.accounts` scope — and answering it from the column rather than deleting it keeps
  # the CHECK constraint and the Ruby saying the same thing. The prefix stays for its own reason:
  # `account?` on a class whose every row is an account reads as a question with no content.
  #
  # 1 AND 2 ARE RETIRED AND NEVER REUSED, on `Category#category_type`'s rule — a backup, an export
  # or a staging database that missed this migration still holds envelopes and goals under those
  # integers, and a fourth pool type takes 3.
  enum :pool_type, { account: 0 }, prefix: true

  scope :accounts, -> { where(pool_type: :account) }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }

  # ** THE MAIN ACCOUNT IS NOT DELETABLE WHILE IT IS MAIN (final fix wave, C-1). ** The one refusal
  # this class still carries, and it is about the PHYSICAL LEDGER rather than about anything nested:
  #
  #   MEASURED, on the shape Home offered before this callback existed. Main is on one side of EVERY
  #   `AccountMovement` the app can write — `Entry#route_income_to!` and `AccountFundingsController
  #   #build_movement` both put `user.default_account` on `from_pool` — so `dependent: :destroy` over
  #   `movements_in`/`movements_out` does not merely take main's own transfers: it takes every
  #   transfer there is. `users.default_account_id` then nullifies (`on_delete: :nullify`),
  #   `AccountLedger#pot` answers 0 because there is no main to read entries against, and every other
  #   account's balance goes to 0 with the movements that fed it. `pot + Σ accounts == 0` while
  #   `available + Σ holdings` stands untouched on the other ledger — two-ledger §2's invariant broken
  #   by one button, with no undo and no screen saying anything happened.
  #
  # RESTRICT-SHAPED RATHER THAN CASCADING, and deliberately: there is no correct thing to do with the
  # user's entire transfer history, so the honest answer is to refuse. This is `restrict_with_error`'s
  # own body (a sentence on `:base`, then `throw :abort`) written by hand because what it restricts on
  # is not an association — it is the `users.default_account_id` pointer aimed back at this row.
  #
  # `prepend: true` so the refusal is decided BEFORE `dependent: :destroy` runs. A halted chain rolls
  # its transaction back either way, so this is not what makes the guard correct — it is what keeps a
  # refused delete from doing thousands of rows of work first.
  #
  # THE ONE ESCAPE IS THE USER'S OWN DELETION. `User has_many :pools, dependent: :destroy` reaches
  # main like any other pool, and a refusal there would make a user undeletable — so the callback
  # stands down when Rails is destroying this row THROUGH that association (`destroyed_by_association`
  # is the reflection then, and nil for every other caller). Nothing is stranded: the user goes with
  # it.
  #
  # NOT A VALIDATION, because `destroy` does not run validations. The controller already checks the
  # return value and renders `errors[:base]`, which is what makes the sentence reach the screen.
  before_destroy :main_account_is_not_deletable, prepend: true

  searchable :name, label: "Name"

  # WHAT THIS ACCOUNT HOLDS, PHYSICALLY — the pot's entries plus every movement in, minus every
  # movement out (`AccountLedger`, spec §2). A door rather than a calculation, for the reason
  # `#calculator` was one before it: a caller that built its own ledger would be a second answer to
  # the question every balance on Home is read from.
  #
  # UNBATCHED, and that is the whole of what this method is for. `AccountLedger` memoises its
  # aggregates at first read, so a screen listing a user's accounts builds ONE and asks it for each
  # account (`HomePresenter`); this is for the single-account questions — a controller's
  # confirmation sentence, a model's refusal — where one ledger is the same number of queries as
  # none.
  def balance = AccountLedger.new(user).balance_of(self)

  # IS THIS THE ACCOUNT EVERYTHING FLOWS THROUGH? `users.default_account_id`, asked of the id rather
  # than of the record so an unloaded association costs no query. The one place the question is
  # spelled — `HomePresenter#main?` and the callback below both come here — because a screen that
  # hid the Delete button on a different account from the one the model refuses would be worse than
  # either half alone.
  def main? = user.present? && user.default_account_id == id

  private

  def main_account_is_not_deletable
    return unless main?
    return if destroyed_by_association

    errors.add(:base, "This is your main account — everything flows through it")
    throw(:abort)
  end
end
