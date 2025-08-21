namespace :cache do
  desc "Clear all Rails and application caches"
  task clear_all: :environment do
    puts "Clearing all caches..."
    
    # Clear Rails cache
    puts "- Clearing Rails cache"
    Rails.cache.clear
    
    # Clear Rails logs
    puts "- Clearing Rails logs"
    system("rake log:clear")
    
    # Clear tmp files
    puts "- Clearing tmp files"
    system("rake tmp:clear")
    
    # Clear assets cache (if using asset pipeline)
    puts "- Clearing assets cache"
    system("rake assets:clobber") if Rails.application.config.assets.enabled
    
    # Clear bootsnap cache (if using bootsnap)
    if defined?(Bootsnap)
      puts "- Clearing Bootsnap cache"
      bootsnap_cache_dir = Rails.root.join("tmp", "cache", "bootsnap*")
      FileUtils.rm_rf(Dir.glob(bootsnap_cache_dir))
    end
    
    # Clear application-specific caches
    puts "- Clearing application-specific caches"
    clear_application_caches
    
    puts "✅ All caches cleared successfully!"
  end
  
  desc "Clear only Rails cache"
  task clear_rails: :environment do
    puts "Clearing Rails cache..."
    Rails.cache.clear
    puts "✅ Rails cache cleared!"
  end
  
  desc "Clear only application-specific caches"
  task clear_app: :environment do
    puts "Clearing application-specific caches..."
    clear_application_caches
    puts "✅ Application caches cleared!"
  end
  
  desc "Show cache statistics"
  task stats: :environment do
    puts "Cache Statistics:"
    puts "=================="
    
    # Show Rails cache info
    puts "Rails Cache Store: #{Rails.cache.class.name}"
    
    # Show application-specific cache keys
    puts "\nApplication Cache Keys:"
    application_cache_keys.each do |key|
      value = Rails.cache.read(key)
      puts "- #{key}: #{value ? 'Present' : 'Not found'}"
    end
    
    # Show tmp directory size
    tmp_size = `du -sh #{Rails.root.join('tmp')} 2>/dev/null | cut -f1`.strip
    puts "\nTmp directory size: #{tmp_size}" unless tmp_size.empty?
  end
  
  private
  
  def clear_application_caches
    # Clear dashboard statistics cache
    Rails.cache.delete("dashboard_statistics")
    
    # Clear recent transactions cache
    Rails.cache.delete("recent_transactions")
    
    # Clear category breakdown cache
    Rails.cache.delete("category_breakdown")
    
    # Clear active anomalies cache
    Rails.cache.delete("active_anomalies")
    
    # Clear unresolved anomalies count cache
    Rails.cache.delete("unresolved_anomalies_count")
    
    # Clear pattern-matched caches
    Rails.cache.delete_matched("transactions_index_*")
    Rails.cache.delete_matched("anomaly_detections_index_*")
    Rails.cache.delete_matched("csv_import_result_*")
    Rails.cache.delete_matched("csv_import_latest_*")
    
    # Clear any other application-specific cache patterns
    Rails.cache.delete_matched("dashboard_*")
    Rails.cache.delete_matched("analytics_*")
  end
  
  def application_cache_keys
    [
      "dashboard_statistics",
      "recent_transactions", 
      "category_breakdown",
      "active_anomalies",
      "unresolved_anomalies_count"
    ]
  end
end