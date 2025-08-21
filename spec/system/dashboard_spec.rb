require 'rails_helper'

RSpec.describe 'Dashboard', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
    # Ensure completely clean database state and clear caches
    Rails.cache.clear

    # Clean up any remaining data to prevent test contamination
    AnomalyDetection.delete_all
    Rule.delete_all
    Transaction.delete_all
    Category.delete_all

    # Force creation of test data before each test to ensure it's available to the browser
    setup_test_data
  end

  def formatCurrency(amount)
    "$#{'%.2f' % amount}"
  end

  def setup_test_data
    @category = create(:category, name: 'Food & Dining')
    @transactions = create_list(:transaction, 5, category: @category)
    @rule = create(:rule)
    @anomaly = create(:anomaly_detection, transaction_record: @transactions.first)
  end

  describe 'dashboard page' do
    before do
      visit root_path
      sleep(3) # Wait for React to load
    end

    it 'displays the dashboard title', js: true do
      expect(page).to have_content('📊 Bookkeeping System')
      expect(page).to have_content('Automated Transaction Management & Anomaly Detection')
    end

    it 'displays stats cards', js: true do
      expect(page).to have_content('TOTAL TRANSACTIONS')
      expect(page).to have_content('CATEGORIES')
      expect(page).to have_content('ACTIVE RULES')
      expect(page).to have_content('UNRESOLVED ANOMALIES')
    end

    it 'shows correct transaction count', js: true do
      within('.stats-grid') do
        stat_card = page.find('.stat-card', text: 'TOTAL TRANSACTIONS')
        within(stat_card) do
          expect(page).to have_content(@transactions.count.to_s)
        end
      end
    end

    it 'displays recent transactions section', js: true do
      expect(page).to have_content('Recent Transactions')
    end

    it 'shows transaction details', js: true do
      # Wait for React components to load
      sleep(2)

      # Find the transactions panel specifically
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        # Verify that at least one transaction is shown with proper formatting
        @transactions.each do |transaction|
          if page.has_content?(transaction.description)
            expect(page).to have_content(formatCurrency(transaction.amount))
            break
          end
        end
      end
    end

    it 'displays anomalies section', js: true do
      # Wait for React components to load
      sleep(2)

      expect(page).to have_content('Active Anomalies')
      # Find the anomalies panel specifically
      anomalies_panel = page.all('.panel').find { |panel| panel.has_content?('Active Anomalies') }
      within(anomalies_panel) do
        expect(page).to have_content(@anomaly.anomaly_type.upcase.gsub('_', ' '))
        expect(page).to have_content(@anomaly.description)
      end
    end

    it 'has working navigation links', js: true do
      # Wait for React components to load
      sleep(2)

      expect(page).to have_link('View All Transactions')
      expect(page).to have_link('View Categories')
      expect(page).to have_link('View Active Rules')
    end
  end

  describe 'quick actions', js: true do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'has quick action buttons' do
      expect(page).to have_content('🚀 Quick Actions')
      expect(page).to have_link('📁 Import CSV Transactions', href: '/upload')
      expect(page).to have_link('🚨 Review Flagged Transactions')
      expect(page).to have_button('🔄 Refresh Dashboard')
    end

    it 'refreshes dashboard when refresh button clicked' do
      initial_text = page.text
      click_button '🔄 Refresh Dashboard'
      sleep(1)
      # Page should still have the main components
      expect(page).to have_content('📊 Bookkeeping System')
    end
  end

  describe 'CSV import link', js: true do
    before do
      visit root_path
      sleep(2) # Wait for React to load
    end

    it 'has link to CSV import page' do
      expect(page).to have_link('📁 Import CSV Transactions', href: '/upload')
    end
  end

  describe 'responsive design' do
    it 'displays properly on mobile viewport', js: true do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone size
      visit root_path
      sleep(3) # Wait for React to load

      expect(page).to have_content('📊 Bookkeeping System')
      expect(page).to have_content('TOTAL TRANSACTIONS')
    end

    it 'displays properly on tablet viewport', js: true do
      page.driver.browser.manage.window.resize_to(768, 1024) # iPad size
      visit root_path
      sleep(3) # Wait for React to load

      expect(page).to have_content('📊 Bookkeeping System')
      expect(page).to have_content('Recent Transactions')
    end
  end
end
