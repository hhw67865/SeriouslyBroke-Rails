import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filterInput", "item", "selectedList", "selectedItems", "emptyMessage", "submitButton"]

  filter() {
    const query = this.filterInputTarget.value.toLowerCase()

    this.itemTargets.forEach(item => {
      const name = item.dataset.filterName
      item.classList.toggle("hidden", query !== "" && !name.includes(query))
    })
  }

  selectionChanged() {
    const checked = this.itemTargets.filter(item => item.querySelector("input:checked"))

    this.selectedItemsTarget.innerHTML = checked.map(item => `
      <div class="flex items-center justify-between py-2 px-1 text-sm">
        <span class="font-medium text-gray-900">${item.dataset.itemName}</span>
        <span class="text-gray-500">${item.dataset.itemEntries} entries &middot; ${item.dataset.itemAmount}</span>
      </div>
    `).join("")

    const hasSelection = checked.length > 0
    this.selectedListTarget.classList.toggle("hidden", !hasSelection)
    this.emptyMessageTarget.classList.toggle("hidden", hasSelection)
    this.submitButtonTarget.disabled = !hasSelection
  }
}
