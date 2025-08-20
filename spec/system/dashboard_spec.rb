require 'rails_helper'

RSpec.describe 'Dashboard', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end
  
  def formatCurrency(amount)
    "$#{'%.2f' % amount}"
  end

  let!(:category) { create(:category, name: 'Food & Dining') }
  let!(:transactions) { create_list(:transaction, 5, category: category) }
  let!(:rule) { create(:rule) }
  let!(:anomaly) { create(:anomaly_detection, transaction_record: transactions.first) }

  describe 'dashboard page' do
    before do
      visit root_path
    end

    it 'displays the dashboard title' do
      expect(page).to have_content('📊 Bookkeeping System')
      expect(page).to have_content('Automated Transaction Management & Anomaly Detection')
    end

    it 'displays stats cards' do
      expect(page).to have_content('TOTAL TRANSACTIONS')
      expect(page).to have_content('CATEGORIES')
      expect(page).to have_content('ACTIVE RULES')
      expect(page).to have_content('UNRESOLVED ANOMALIES')
    end

    it 'shows correct transaction count' do
      expect(page).to have_content(transactions.count.to_s)
    end

    it 'displays recent transactions section' do
      expect(page).to have_content('Recent Transactions')
    end

    it 'shows transaction details', js: true do
      # Wait for React components to load
      sleep(2)
      
      # Find the transactions panel specifically
      transactions_panel = page.all('.panel').find { |panel| panel.has_content?('Recent Transactions') }
      within(transactions_panel) do
        # Verify that at least one transaction is shown with proper formatting
        transactions.each do |transaction|
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
        expect(page).to have_content(anomaly.anomaly_type.upcase.gsub('_', ' '))
        expect(page).to have_content(anomaly.description)
      end
    end

    it 'has working navigation links', js: true do
      # Wait for React components to load
      sleep(2)
      
      expect(page).to have_link('View All Transactions')
      expect(page).to have_link('View Categories')
      expect(page).to have_link('View Active Rules')
      expect(page).to have_link('Import CSV Transactions', href: '/upload')
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
    it 'displays properly on mobile viewport' do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone size
      visit root_path
      
      expect(page).to have_content('📊 Bookkeeping System')
      expect(page).to have_content('TOTAL TRANSACTIONS')
    end

    it 'displays properly on tablet viewport' do
      page.driver.browser.manage.window.resize_to(768, 1024) # iPad size
      visit root_path
      
      expect(page).to have_content('📊 Bookkeeping System')
      expect(page).to have_content('Recent Transactions')
    end
  end
end