import { Controller } from "@hotwired/stimulus"

// Manages the responsive menu in the landing page navigation
export default class extends Controller {
  static targets = ["content", "openIcon", "closeIcon"]

  connect() {
    // Close menu when clicking outside
    document.addEventListener('click', this.handleClickOutside.bind(this))
  }

  disconnect() {
    document.removeEventListener('click', this.handleClickOutside.bind(this))
  }

  toggle() {
    this.contentTarget.classList.toggle('hidden')
    this.openIconTarget.classList.toggle('hidden')
    this.closeIconTarget.classList.toggle('hidden')
  }

  close() {
    this.contentTarget.classList.add('hidden')
    this.openIconTarget.classList.remove('hidden')
    this.closeIconTarget.classList.add('hidden')
  }

  handleClickOutside(event) {
    // Don't close if clicking inside the menu or on the menu button
    if (this.element.contains(event.target)) return

    this.close()
  }
} 