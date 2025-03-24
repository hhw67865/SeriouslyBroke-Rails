class BudgetsController < ResourceController
  private

  def resource_params
    params.require(:budget).permit(:amount, :period, :category_id)
  end
end 