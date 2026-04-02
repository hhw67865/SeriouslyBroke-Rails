import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "selectAll", "toolbar", "selectedCount"]

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.visibleCheckboxes.forEach(cb => cb.checked = checked)
    this.updateToolbar()
  }

  selectionChanged() {
    const visible = this.visibleCheckboxes
    const allChecked = visible.every(cb => cb.checked)
    const someChecked = visible.some(cb => cb.checked)

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = allChecked
      this.selectAllTarget.indeterminate = someChecked && !allChecked
    }

    this.updateToolbar()
  }

  updateToolbar() {
    const count = this.selectedCount
    this.selectedCountTarget.textContent = count
  }

  get selectedCount() {
    return this.visibleCheckboxes.filter(cb => cb.checked).length
  }

  get visibleCheckboxes() {
    return this.checkboxTargets.filter(cb => cb.offsetParent !== null)
  }
}
