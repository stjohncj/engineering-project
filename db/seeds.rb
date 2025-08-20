# Create sample categories
categories = [
  { name: 'Food & Dining', description: 'Restaurants, groceries, food delivery', color: '#FF6B6B' },
  { name: 'Transportation', description: 'Gas, public transport, rideshare', color: '#4ECDC4' },
  { name: 'Shopping', description: 'Clothing, electronics, general retail', color: '#45B7D1' },
  { name: 'Entertainment', description: 'Movies, games, streaming services', color: '#96CEB4' },
  { name: 'Bills & Utilities', description: 'Rent, electricity, internet, phone', color: '#FFEAA7' },
  { name: 'Healthcare', description: 'Medical appointments, pharmacy, insurance', color: '#DDA0DD' },
  { name: 'Income', description: 'Salary, freelance payments, refunds', color: '#98D8C8' }
]

puts "Creating categories..."
categories.each do |cat_data|
  Category.find_or_create_by(name: cat_data[:name]) do |category|
    category.description = cat_data[:description]
    category.color = cat_data[:color]
  end
end

# Create sample rules
rules = [
  {
    name: 'Categorize Amazon purchases',
    condition_field: 'description',
    condition_operator: 'contains',
    condition_value: 'amazon',
    action_type: 'categorize',
    action_value: 'Shopping',
    active: true
  },
  {
    name: 'Categorize Uber rides',
    condition_field: 'description',
    condition_operator: 'contains',
    condition_value: 'uber',
    action_type: 'categorize',
    action_value: 'Transportation',
    active: true
  },
  {
    name: 'Flag large transactions',
    condition_field: 'amount',
    condition_operator: 'greater_than',
    condition_value: '1000',
    action_type: 'flag',
    action_value: 'Large transaction',
    active: true
  },
  {
    name: 'Categorize salary payments',
    condition_field: 'description',
    condition_operator: 'contains',
    condition_value: 'salary',
    action_type: 'categorize',
    action_value: 'Income',
    active: true
  }
]

puts "Creating rules..."
rules.each do |rule_data|
  Rule.find_or_create_by(name: rule_data[:name]) do |rule|
    rule.condition_field = rule_data[:condition_field]
    rule.condition_operator = rule_data[:condition_operator]
    rule.condition_value = rule_data[:condition_value]
    rule.action_type = rule_data[:action_type]
    rule.action_value = rule_data[:action_value]
    rule.active = rule_data[:active]
  end
end

# Create sample transactions
sample_transactions = [
  { amount: 12.50, description: 'Starbucks Coffee', transaction_date: 1.day.ago },
  { amount: 45.30, description: 'Grocery shopping at Whole Foods', transaction_date: 2.days.ago },
  { amount: 15.00, description: 'Uber ride to downtown', transaction_date: 3.days.ago },
  { amount: 89.99, description: 'Amazon purchase - electronics', transaction_date: 4.days.ago },
  { amount: 1200.00, description: 'Monthly rent payment', transaction_date: 5.days.ago },
  { amount: 25.00, description: 'Netflix subscription', transaction_date: 1.week.ago },
  { amount: 2500.00, description: 'Monthly salary deposit', transaction_date: 1.week.ago },
  { amount: 67.89, description: 'Gas station fill-up', transaction_date: 10.days.ago },
  { amount: 150.00, description: 'Doctor appointment copay', transaction_date: 2.weeks.ago },
  { amount: 5000.00, description: 'Suspicious large transfer', transaction_date: 1.day.ago }
]

puts "Creating sample transactions..."
sample_transactions.each do |tx_data|
  transaction = Transaction.create!(
    amount: tx_data[:amount],
    description: tx_data[:description],
    transaction_date: tx_data[:transaction_date],
    status: :pending
  )
  
  # Apply rules to the transaction
  Rule.active.each do |rule|
    rule.apply_to!(transaction)
  end
  
  # Run anomaly detection
  AnomalyDetectionService.new(transaction).detect_and_flag
end

puts "Seed data created successfully!"
puts "Categories: #{Category.count}"
puts "Rules: #{Rule.count}"
puts "Transactions: #{Transaction.count}"
puts "Anomaly Detections: #{AnomalyDetection.count}"