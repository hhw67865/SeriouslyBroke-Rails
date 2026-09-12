# frozen_string_literal: true

# Shared classes for a rule's two doors (the Edit link and the Adjust summary), so the two
# controls can't drift out of visual sync with each other.
module RuleActionsHelper
  RULE_ACTION_CLASSES =
    "inline-block w-full rounded border border-gray-200 py-2.5 text-center text-brand-dark " \
    "hover:bg-gray-50 sm:w-auto sm:rounded-none sm:border-0 sm:p-0 sm:hover:bg-transparent " \
    "sm:hover:text-brand"

  # The shared skin plus whatever ONE of the two needs on its own: the side it aligns to above `sm`,
  # and the summary's own cursor and size, which the `Edit` link inherits from the row it sits in.
  def rule_action_classes(*extra) = [RULE_ACTION_CLASSES, *extra].join(" ")
end
