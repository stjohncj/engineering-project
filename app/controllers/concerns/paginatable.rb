module Paginatable
  extend ActiveSupport::Concern
  
  # Default pagination settings optimized for large datasets
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100
  
  private
  
  def paginate_collection(collection)
    page = params[:page]&.to_i || 1
    per_page = [(params[:per_page]&.to_i || DEFAULT_PER_PAGE), MAX_PER_PAGE].min
    
    # Use limit/offset for manual pagination if Kaminari is not available
    if collection.respond_to?(:page)
      # Kaminari pagination (preferred)
      paginated = collection.page(page).per(per_page)
    else
      # Manual pagination fallback
      offset = (page - 1) * per_page
      paginated = collection.offset(offset).limit(per_page)
    end
    
    paginated
  end
  
  def pagination_meta(collection, current_page = nil, per_page = nil)
    current_page ||= params[:page]&.to_i || 1
    per_page ||= [(params[:per_page]&.to_i || DEFAULT_PER_PAGE), MAX_PER_PAGE].min
    
    if collection.respond_to?(:total_count)
      # Kaminari methods
      {
        current_page: collection.current_page,
        per_page: collection.limit_value,
        total_count: collection.total_count,
        total_pages: collection.total_pages,
        next_page: collection.next_page,
        prev_page: collection.prev_page
      }
    else
      # Manual pagination meta
      total_count = get_total_count(collection)
      total_pages = (total_count.to_f / per_page).ceil
      
      {
        current_page: current_page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages,
        next_page: current_page < total_pages ? current_page + 1 : nil,
        prev_page: current_page > 1 ? current_page - 1 : nil
      }
    end
  end
  
  def get_total_count(collection)
    # Try to get count efficiently, with caching for expensive counts
    base_relation = collection.except(:offset, :limit, :order)
    
    cache_key = "total_count_#{base_relation.to_sql.hash}"
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      base_relation.count
    end
  end
  
  def paginated_json(collection, data_key: :data, serializer: nil)
    pagination_info = pagination_meta(collection)
    
    {
      data_key => serializer ? collection.map(&serializer) : collection,
      pagination: pagination_info
    }
  end
end