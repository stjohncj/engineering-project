class Api::V1::CategoriesController < ApplicationController
  before_action :set_category, only: [ :show, :update, :destroy ]

  def index
    # Cache categories list for 30 minutes since they don't change frequently
    categories_data = Rails.cache.fetch("categories_index", expires_in: 30.minutes) do
      Category.left_joins(:transactions)
              .select("categories.*, COUNT(transactions.id) as transaction_count, COALESCE(SUM(transactions.amount), 0) as total_amount")
              .group("categories.id")
              .order(:name)
              .map { |c| category_json(c, include_stats: true) }
    end

    # Set HTTP cache headers
    expires_in 30.minutes, public: true

    render json: {
      categories: categories_data
    }
  end

  def show
    # Cache individual category with stats
    category_data = Rails.cache.fetch("category_#{@category.id}_with_stats", expires_in: 15.minutes) do
      category_with_stats = Category.left_joins(:transactions)
                                   .select("categories.*, COUNT(transactions.id) as transaction_count, COALESCE(SUM(transactions.amount), 0) as total_amount")
                                   .group("categories.id")
                                   .find(@category.id)
      category_json(category_with_stats, include_stats: true)
    end

    expires_in 15.minutes, public: true
    render json: { category: category_data }
  end

  def create
    @category = Category.new(category_params)

    if @category.save
      # Invalidate categories cache
      invalidate_category_caches

      render json: { category: category_json(@category) }, status: :created
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @category.update(category_params)
      # Invalidate categories cache
      invalidate_category_caches

      render json: { category: category_json(@category) }
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy
    head :no_content
  end

  private

  def set_category
    @category = Category.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Category not found" }, status: :not_found
  end

  def category_params
    params.require(:category).permit(:name, :description, :color)
  end

  def category_json(category, include_stats: false)
    json = {
      id: category.id,
      name: category.name,
      description: category.description,
      color: category.color,
      created_at: category.created_at,
      updated_at: category.updated_at
    }

    if include_stats
      # Use attributes from SQL aggregation if available, otherwise calculate
      if category.respond_to?(:transaction_count)
        json[:stats] = {
          transaction_count: category.transaction_count.to_i,
          total_amount: category.total_amount.to_f
        }
      else
        # Fallback for individual categories without aggregation
        json[:stats] = Rails.cache.fetch("category_#{category.id}_stats", expires_in: 10.minutes) do
          {
            transaction_count: category.transactions.count,
            total_amount: category.transactions.sum(:amount).to_f
          }
        end
      end
    end

    json
  end

  def invalidate_category_caches
    Rails.cache.delete("categories_index")
    Rails.cache.delete("category_breakdown")
    Rails.cache.delete_matched("category_*_stats")
    Rails.cache.delete_matched("category_*_with_stats")
  end
end
