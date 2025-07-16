import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="shared--search-placeholder"
export default class extends Controller {
  static targets = ["fieldSelector", "searchInput"]
  static values = { placeholders: Object }

  connect() {
    // Update placeholder on initial load if field is already selected
    this.updatePlaceholder()
  }

  // Called when the field selector changes
  fieldChanged() {
    this.updatePlaceholder()
  }

  updatePlaceholder() {
    const selectedField = this.fieldSelectorTarget.value
    const placeholder = this.placeholdersValue[selectedField] || 'Enter search term...'
    this.searchInputTarget.placeholder = placeholder
  }
} 