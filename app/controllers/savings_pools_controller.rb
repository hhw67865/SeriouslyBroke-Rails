class SavingsPoolsController < ResourceController
  private

  def resource_params
    params.require(:savings_pool).permit(:name, :target_amount)
  end
end
