class ItemsController < ResourceController
  private

  def resource_params
    params.require(:item).permit(:name, :description, :frequency, :category_id)
  end
end
