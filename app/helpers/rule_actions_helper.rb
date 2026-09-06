# frozen_string_literal: true

# ** THE TWO DOORS ONTO A RULE WEAR ONE SKIN, AND THIS IS WHERE IT IS SPELLED (mobile pass fix
# round, 2026-09-06). ** `Edit` (`budget_page/_category_open`) and the `Adjust` summary
# (`budget_page/_adjust`) sit one under the other inside a rule's row. Below `sm` they are
# full-width buttons — they measured **25×20** and **41×20**, two words as the only way into a
# rule's declaration and into this period's money, on the screen where a finger is doing the
# pressing — and from `sm` they are the underlined link and the bare summary the desktop column was
# designed with. `py-2.5` is 40px once the border is counted, the target minimum that pass held
# everything to.
#
# ** IT IS ONE STRING BECAUSE THE FIRST VERSION WAS A PROMISE. ** The classes were typed into both
# partials with a note in each saying they matched the other, and they did not: one copy had lost
# `sm:hover:text-brand`, so the desktop link stopped changing colour under the pointer and nothing
# on the screen or in the suite said so. Two controls that must look identical cannot be kept
# identical by a comment.
#
# ** ITS OWN MODULE, AND NOT `BudgetPageHelper`. ** That module is at RuboCop's limit for one, and a
# shared SKIN is a different concern from that file's subject, which is the page's words — what a
# rule is called, what a cadence reads as, what order the arrows write.
module RuleActionsHelper
  RULE_ACTION_CLASSES =
    "inline-block w-full rounded border border-gray-200 py-2.5 text-center text-brand-dark " \
    "hover:bg-gray-50 sm:w-auto sm:rounded-none sm:border-0 sm:p-0 sm:hover:bg-transparent " \
    "sm:hover:text-brand"

  # The shared skin plus whatever ONE of the two needs on its own: the side it aligns to above `sm`,
  # and the summary's own cursor and size, which the `Edit` link inherits from the row it sits in.
  def rule_action_classes(*extra) = [RULE_ACTION_CLASSES, *extra].join(" ")
end
