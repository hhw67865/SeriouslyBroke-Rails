import { Controller } from "@hotwired/stimulus"

// Handles the category form interactions
export default class extends Controller {
  static targets = [
    "categoryTypeOption", 
    "categoryTypeIcon", 
    "categoryTypeText", 
    "colorOption", 
    "colorInput",
    "selectedColorPreview",
    "selectedColorCode"
  ]

  connect() {
    // Initialize the form state if needed
    this.updateCategoryTypeUI()
    this.updateColorSelection()
  }

  // Category Type Selection
  selectCategoryType(event) {
    const selectedValue = event.currentTarget.value
    this.updateCategoryTypeUI(selectedValue)
  }

  updateCategoryTypeUI(selectedValue = null) {
    // If no value is provided, use the currently selected radio button
    if (!selectedValue) {
      const selectedRadio = this.element.querySelector('input[name="category[category_type]"]:checked')
      selectedValue = selectedRadio ? selectedRadio.value : null
    }

    if (!selectedValue) return

    // Reset all options to default state
    this.categoryTypeOptionTargets.forEach(option => {
      option.classList.remove('border-brand', 'bg-brand-light')
      option.classList.add('border-gray-200')
    })
    
    this.categoryTypeIconTargets.forEach(icon => {
      icon.classList.remove('bg-brand')
      icon.classList.add('bg-gray-200')
    })
    
    this.categoryTypeTextTargets.forEach(text => {
      text.classList.remove('text-gray-900')
      text.classList.add('text-gray-700')
    })
    
    // Highlight the selected option
    const selectedOption = this.element.querySelector(`.category-type-option[data-type="${selectedValue}"]`)
    if (selectedOption) {
      selectedOption.classList.remove('border-gray-200')
      selectedOption.classList.add('border-brand', 'bg-brand-light')
      
      const icon = selectedOption.querySelector('.category-type-icon')
      if (icon) {
        icon.classList.remove('bg-gray-200')
        icon.classList.add('bg-brand')
      }
      
      const text = selectedOption.querySelector('.category-type-text')
      if (text) {
        text.classList.remove('text-gray-700')
        text.classList.add('text-gray-900')
      }
    }
  }

  // Color Selection
  selectColor(event) {
    const selectedColor = event.currentTarget.value
    this.updateColorInput(selectedColor)
    this.updateColorSelection(selectedColor)
    this.updateColorPreview(selectedColor)
  }

  updateColorInput(color) {
    if (this.hasColorInputTarget) {
      this.colorInputTarget.value = color
    }
  }

  updateColorSelection(selectedColor = null) {
    // If no color is provided, use the currently selected radio button
    if (!selectedColor) {
      const selectedRadio = this.element.querySelector('input[name="category[color]"]:checked')
      selectedColor = selectedRadio ? selectedRadio.value : null
    }

    // Reset all options to default state
    this.colorOptionTargets.forEach(option => {
      option.classList.remove('ring-2', 'ring-offset-2', 'ring-gray-700')
    })
    
    // Highlight the selected option if it exists
    if (selectedColor) {
      const selectedOption = this.element.querySelector(`.color-option[data-color="${selectedColor}"]`)
      if (selectedOption) {
        selectedOption.classList.add('ring-2', 'ring-offset-2', 'ring-gray-700')
      }
      
      // Update the color preview
      this.updateColorPreview(selectedColor)
    }
  }
  
  // Update color preview elements
  updateColorPreview(color) {
    if (this.hasSelectedColorPreviewTarget) {
      this.selectedColorPreviewTarget.style.backgroundColor = color
    }
    
    if (this.hasSelectedColorCodeTarget) {
      this.selectedColorCodeTarget.textContent = color
    }
  }

  // Handle color input field changes
  colorInputChanged(event) {
    const colorValue = event.currentTarget.value
    
    // Update the preview immediately
    this.updateColorPreview(colorValue)
    
    // Find matching radio button
    const matchingRadio = this.element.querySelector(`.color-radio[value="${colorValue}"]`)
    if (matchingRadio) {
      matchingRadio.checked = true
      this.updateColorSelection(colorValue)
    } else {
      // If no matching color, deselect all
      this.colorOptionTargets.forEach(option => {
        option.classList.remove('ring-2', 'ring-offset-2', 'ring-gray-700')
      })
    }
  }
} 