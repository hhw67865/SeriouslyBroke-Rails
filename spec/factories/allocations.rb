# frozen_string_literal: true

FactoryBot.define do
  # A MOVE ON THE PURPOSE LEDGER, AND ITS DEFAULT SHAPE IS "AVAILABLE → A CATEGORY" — the one
  # every other allocation is a variation of. `from_category` is left NULL because NULL is not a
  # missing value here: it is AVAILABLE, the root every allocation ultimately draws on
  # (two-ledger spec §2). A fixture that wants the other three shapes says so — `from_category:`
  # for a withdrawal back to available, both sides for a hand move between two categories.
  #
  # `:funded` on the association rather than a bare `:category`, because an allocation is one of
  # the two things that MAKE a category a holder: a category that has been allocated to and has no
  # `funded_since` holds money its own spending cannot drain (`CategoryLedger::ENTRY_CATEGORY_ID`
  # sends every entry of an unfunded category to available), which is a shape the app writes
  # nowhere and no fixture should reach for by accident.
  #
  # THE DEFAULT DESTINATION STANDS DOWN THE MOMENT A CALLER NAMES A SOURCE. Without that, a fixture
  # saying `create(:allocation, from_category: food)` — a withdrawal back to available, the second
  # of the four shapes — silently gets a minted destination category belonging to a minted OTHER
  # USER, and `Allocation`'s own "must stay within one user" refuses the row. Reading
  # `from_category` from inside the block is FactoryBot's own way of asking what the caller
  # supplied, and it is the one place this default can be made conditional.
  factory :allocation do
    amount { 100 }
    date { Time.zone.now }
    kind { :transfer }
    from_category { nil }
    to_category { from_category.nil? ? association(:category, :expense, :funded) : nil }
  end
end
