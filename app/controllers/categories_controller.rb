class CategoriesController < ResourceController
  private

  def resource_params
    params.require(:category).permit(:name, :category_type, :color, :savings_pool_id)
  end
end
