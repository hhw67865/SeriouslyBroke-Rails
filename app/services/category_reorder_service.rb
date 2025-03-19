class CategoryReorderService
  def initialize(user)
    @user = user
  end

  def reorder(category_ids)
    @user.transaction do
      categories = @user.categories.where(id: category_ids).order(:order)
      order_numbers = categories.pluck(:order)

      @user.categories.where(id: category_ids).update_all(order: nil)

      order_numbers.each_with_index do |number, index|
        @user.categories.find_by(id: category_ids[index]).update(order: number)
      end
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end
end