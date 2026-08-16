# frozen_string_literal: true

# DOM facts a system spec can assert about the WHOLE rendered page, chrome included — the things
# no single screen's spec owns and every screen's spec can be broken by.
module DomHelpers
  # Every id appearing more than once in the document.
  #
  # Duplicate ids are invalid HTML and they are a SILENT trap rather than a cosmetic one: both
  # `label for=` and `document.getElementById` resolve to the first match in the document, so a
  # screen whose form field shares an id with something in the sidebar quietly hands the label,
  # the script and the screen reader a different element than the one the user types in. Capybara
  # filters invisible elements, so an example that goes through `fill_in` lands on the right one
  # by luck and passes either way — which is exactly why this has to be asserted directly.
  #
  # Found on Task 7's reallocation screen, where `shared/_date_selector` re-emitted every scalar
  # query parameter as a hidden field with an id in each of its four forms.
  def duplicate_dom_ids
    page.evaluate_script(<<~JS)
      (() => {
        const seen = new Set(), duplicated = new Set();
        document.querySelectorAll("[id]").forEach((element) => {
          if (seen.has(element.id)) { duplicated.add(element.id); }
          seen.add(element.id);
        });
        return Array.from(duplicated);
      })()
    JS
  end
end

RSpec.configure do |config|
  config.include DomHelpers, type: :system
end
