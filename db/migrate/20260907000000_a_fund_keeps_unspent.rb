# frozen_string_literal: true

# ** ONE COLUMN, AND IT BRINGS BACK THE SHAPE THE TWO SHAPES RETIRED (two-shapes spec §12, Henry's
# ruling of 2026-09-06). **
#
#   > "I tried to set a $510 rule per period on BaBay Duck but there was no option to have it grow
#   > endlessly (no limit)… Basically the claimed for the rule would be the total every period minus
#   > any adjustments made. And it will keep growing. So the claim amount will grow."
#
# §1 retired the open-ended shape on the reasoning that "an emergency fund is $10,000 by next
# September". That reasoning holds for a GOAL and not for an allowance a household simply wants to
# carry forward: a pet-care envelope has no day it is needed on, no figure it is aiming at, and the
# whole point of it is that a quiet month leaves more in it. `budgets.keeps_unspent` is the one
# column that says so, and `ClaimCalculator#shape` reads it as a third arm (`:fund`).
#
# ** ADDITIVE, WITH A DEFAULT, AND THAT IS THE WHOLE MIGRATION. ** Every existing rule is a rule
# whose unspent money resets — that is what every screen has been saying about it since `TwoShapes` —
# so `false` is not a fallback here, it is the truth about every row this migration meets. There is
# no data to convert, no claim to re-derive and no receipt to print: the figure a user was looking at
# yesterday is the figure they see today, and only a rule they tick the new box on ever changes.
#
# ** `NOT NULL` RATHER THAN A NULLABLE FLAG. ** A three-valued "keeps unspent" would give `#shape` a
# state with no answer — neither an allowance nor a fund — and the model would have to guess. The
# question has two answers for every rule that exists.
#
# ** A DATED RULE NEVER KEEPS, AND THE REFUSAL IS THE MODEL'S (`Budget#keeps_unspent_never_dates`)
# RATHER THAN A CHECK CONSTRAINT. ** The pair is a form-level coherence rule — "Keeps what it doesn't
# spend" is a checkbox under "Every period" and is not offered under "By a date" — and it belongs
# where the sentence a user reads can be attached to the control that produced it. `TightenPoolShape`
# is the cautionary precedent: a CHECK added past the model is a shape no fixture can plant even
# deliberately, which is what forced `spec/support/schema_rewind.rb` into existence.
#
# `down` REMOVES THE COLUMN, which is a true reversal here: nothing is derived from it and no other
# column is written on the strength of it, so a rule that kept its unspent money becomes a rule that
# does not — the same row the database held before the column existed.
class AFundKeepsUnspent < ActiveRecord::Migration[8.1]
  def up
    add_column :budgets, :keeps_unspent, :boolean, default: false, null: false
  end

  def down
    remove_column :budgets, :keeps_unspent
  end
end
