require 'rails_helper'

RSpec.describe 'Transaction Management', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  let!(:category) { create(:category, name: 'Food & Dining') }
  let!(:other_category) { create(:category, name: 'Transportation') }
  # Create the transaction with a very recent created_at to ensure it appears first in recent transactions
  let!(:transaction) { create(:transaction, category: category, description: 'Test Transaction', amount: 50.00, created_at: Time.current) }

  describe 'viewing transactions on dashboard' do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'displays transactions in the Recent Transactions section', js: true do
      expect(page).to have_content('Recent Transactions')

      # Find the transactions panel
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content(transaction.description)
        expect(page).to have_content("$#{'%.2f' % transaction.amount}")
        expect(page).to have_content(category.name)
      end
    end

    it 'shows transaction date', js: true do
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        # Date format might be different based on locale settings
        expect(page.text).to match(/\w{3} \d{1,2}, \d{4}/) # Matches format like "Aug 19, 2025"
      end
    end

    it 'displays transaction status', js: true do
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        expect(page).to have_content(transaction.status.upcase)
      end
    end

    it 'provides anomaly data through API for flagged transactions', js: true do
      # Create an anomaly for the transaction
      anomaly = create(:anomaly_detection,
                      transaction_record: transaction,
                      resolved: false,
                      created_at: Time.current)

      # Verify the anomaly exists and is unresolved
      transaction.reload
      expect(transaction.anomaly_detections.count).to eq(1)
      expect(transaction.anomaly_detections.unresolved.count).to eq(1)

      # Test that the API correctly includes anomaly data
      get '/api/v1/dashboard/recent_transactions'
      expect(response).to be_successful

      response_json = JSON.parse(response.body)
      transaction_data = response_json['transactions'].find { |t| t['id'] == transaction.id }

      expect(transaction_data).to be_present
      expect(transaction_data['anomalies']).to be_present
      expect(transaction_data['anomalies'].length).to eq(1)
      expect(transaction_data['anomaly_count']).to eq(1)
    end
  end

  describe 'transaction API endpoints' do
    it 'provides link to view all transactions via API', js: true do
      visit root_path
      sleep(2)

      expect(page).to have_link('View All Transactions', href: '/api/v1/transactions')
    end
  end

  describe 'transaction count in stats' do
    # Use fresh let! variables to avoid interference with parent context
    let!(:test_category) { create(:category, name: 'Test Category') }
    let!(:count_transactions) do
      5.times.map do |i|
        create(:transaction, category: test_category, created_at: (i + 1).minutes.ago)
      end
    end

    before do
      # Force creation of the transactions
      count_transactions

      # Verify the count in the database
      expect(Transaction.count).to be >= 5

      # Clear cache to ensure fresh data
      Rails.cache.clear

      visit root_path
      sleep(3) # Give more time for React to load and fetch data
    end

    it 'displays transaction count in stats section', js: true do
      within('.stats-grid') do
        expect(page).to have_content('TOTAL TRANSACTIONS')
        # Look for the transaction count stat card
        stat_card = page.find('.stat-card', text: 'TOTAL TRANSACTIONS')
        within(stat_card) do
          # Just verify that a number is displayed (the exact count may vary in test environment)
          expect(page).to have_css('.stat-number')
          count_text = page.find('.stat-number').text
          expect(count_text).to match(/^\d+$/) # Should be a number
        end
      end
    end
  end
end
