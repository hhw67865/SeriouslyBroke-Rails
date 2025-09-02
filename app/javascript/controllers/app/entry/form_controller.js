import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["itemSelect", "itemNameField", "categorySelect"]

  connect() {
    this.initializeItemSelect()
    this.initializeCategorySelect()
  }

  initializeItemSelect() {
    this.itemSelect = new TomSelect(this.itemSelectTarget, {
      create: (input) => {
        this.itemNameFieldTarget.value = input
        return { text: input, value: "" }
      },
      onChange: (value) => {
        if (value === "") {
          const selectedItem = this.itemSelect.getItem(value)
          this.itemNameFieldTarget.value = selectedItem ? selectedItem.textContent : ""
        } else {
          this.itemNameFieldTarget.value = ""
        }
      }
    })
  }

  initializeCategorySelect() {
    this.categorySelect = new TomSelect(this.categorySelectTarget, {
      create: (input) => {
        this.updateItemSelect(null)
        return { text: `Create "${input}"`, value: "" }
      },
      onChange: (value) => {
        if (value === "") {
          // User created a new category - clear items
          this.updateItemSelect(null)
        } else {
          // User selected existing category - fetch its items
          this.fetchItemsForCategory(value)
        }
      }
    })
  }
  
  updateItemSelect(items) {
    if (this.itemSelect) {
      this.itemSelect.destroy()
    }
  
    if (items === null) {
      this.itemSelectTarget.innerHTML = '<option value="">Create an item</option>'
    } else {
      this.itemSelectTarget.innerHTML = '<option value="">Select or Create an item</option>' +
        items.map(item => `<option value="${item.id}">${item.name}</option>`).join('')
    }
  
    this.initializeItemSelect()
  }
  
  fetchItemsForCategory(categoryId) {
    fetch(`/categories/${categoryId}/items`)
      .then(response => response.json())
      .then(items => {
        this.updateItemSelect(items)
      })
      .catch(error => {
        console.error("Error fetching items:", error)
        this.updateItemSelect(null)
      })
  }
}