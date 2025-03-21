import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Automatically hide flash messages after 5 seconds
    setTimeout(() => {
      this.close()
    }, 5000)
  }

  close() {
    this.element.remove()
  }
} 