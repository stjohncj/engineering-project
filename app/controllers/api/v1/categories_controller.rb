class Api::V1::CategoriesController < ApplicationController
  before_action :set_category, only: [:show, :update, :destroy]
  
  def index
    @categories = Category.all.includes(:transactions)
    
    render json: {
      categories: @categories.map { |c| category_json(c) }
    }
  end
  
  def show
    render json: { category: category_json(@category, include_stats: true) }
  end
  
  def create
    @category = Category.new(category_params)
    
    if @category.save
      render json: { category: category_json(@category) }, status: :created
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  def update
    if @category.update(category_params)
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
      json[:stats] = {
        transaction_count: category.transaction_count,
        total_amount: category.total_amount.to_f
      }
    end
    
    json
  end
end