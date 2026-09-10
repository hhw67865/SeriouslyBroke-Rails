import { Controller } from "@hotwired/stimulus"

// The Usual strip follows the form's category: only that category's chips stay, and with no
// category every chip is back. Nothing is fetched; the chips carry their category id.
export default class extends Controller {
  static targets = ["chip", "empty"]

  connect() {
    const select = document.querySelector('[data-app--entry--form-target="categorySelect"]')
    this.narrowTo(select ? select.value : "")
  }

  filter(event) {
    this.narrowTo(event.detail.categoryId)
  }

  narrowTo(categoryId) {
    let shown = 0
    this.chipTargets.forEach((chip) => {
      const visible = categoryId === "" || chip.dataset.categoryId === categoryId
      chip.hidden = !visible
      if (visible) shown += 1
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
  }
}
