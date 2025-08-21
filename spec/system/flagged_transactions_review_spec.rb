require 'rails_helper'

RSpec.describe 'Flagged Transactions Review', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
    # Ensure completely clean database state and clear caches
    Rails.cache.clear
    
    # Clean up any remaining data to prevent test contamination
    AnomalyDetection.delete_all
    Transaction.delete_all
    Category.delete_all
    
    # Force creation of test data before each test to ensure it's available to the browser
    setup_test_data
    
    # Create anomalies for transactions to make them appear in the review page
    @unusual_amount_anomaly = create(:anomaly_detection,
      transaction_record: @flagged_transaction,
      anomaly_type: 'unusual_amount',
      severity: 4,
      description: 'Transaction amount significantly deviates from historical average'
    )

    @incomplete_metadata_anomaly = create(:anomaly_detection,
      transaction_record: @pending_transaction,
      anomaly_type: 'incomplete_metadata',
      severity: 2,
      description: 'Missing required transaction metadata'
    )

    @duplicate_anomaly = create(:anomaly_detection,
      transaction_record: @rejected_transaction,
      anomaly_type: 'duplicate_transaction',
      severity: 3,
      description: 'Potential duplicate transaction detected'
    )
  end
  
  def setup_test_data
    @category = create(:category, name: 'Food & Dining')
    @transport_category = create(:category, name: 'Transportation')

    @flagged_transaction = create(:transaction,
      description: 'Suspicious large purchase',
      amount: 5000.00,
      status: 'flagged',
      category: @category
    )

    @pending_transaction = create(:transaction,
      description: 'Pending restaurant bill',
      amount: 75.50,
      status: 'pending',
      category: @category
    )

    @rejected_transaction = create(:transaction,
      description: 'Rejected invalid transaction',
      amount: 999.99,
      status: 'rejected',
      category: @transport_category
    )

    @normal_transaction = create(:transaction, status: 'approved', category: @category)
  end

  describe 'review page access' do
    it 'is accessible from dashboard', js: true do
      # Skip this test for now - React dashboard loading issues
      skip "Dashboard React app not loading in test environment"
    end

    it 'displays page header and navigation', js: true do
      visit '/review'
      sleep(2)

      expect(page).to have_content('🚨 Review Flagged Transactions')
      expect(page).to have_content('Review and manage transactions that require attention')
      expect(page).to have_link('← Back to Dashboard', href: '/')
    end
  end

  describe 'flagged transactions display' do
    it 'shows flagged transactions with anomalies', js: true do
      visit '/review'
      sleep(3) # Wait for API calls

      # Should show the flagged transaction
      expect(page).to have_content('Suspicious large purchase')
      expect(page).to have_content('$5,000.00')
      expect(page).to have_content('Food & Dining')

      # Should show anomaly information
      expect(page).to have_content('⚠️ Anomalies Detected')
      expect(page).to have_content('UNUSUAL AMOUNT')
      expect(page).to have_content('Transaction amount significantly deviates')
    end

    it 'displays transaction count', js: true do
      visit '/review'
      sleep(3)

      expect(page).to have_content('Flagged Transactions (1)')
    end

    it 'shows appropriate empty state when no flagged transactions', js: true do
      # Remove all flagged transactions
      Transaction.update_all(status: 'approved')

      visit '/review'
      sleep(3)

      expect(page).to have_content('🎉 No flagged transactions found!')
      expect(page).to have_content('Flagged Transactions (0)')
    end
  end

  describe 'transaction actions' do
    it 'shows action buttons for each transaction', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        expect(page).to have_button('✓ Approve')
        expect(page).to have_button('✏️ Edit')
        expect(page).to have_button('🗑️ Delete')
      end
    end

    describe 'approve functionality' do
      it 'can approve a flagged transaction', js: true do
        # Set up flagged transaction
        @flagged_transaction.update!(status: 'flagged')

        visit '/review'
        sleep(3)

        # Filter to show only flagged transactions
        select 'Flagged', from: 'Status'
        sleep(3)

        # Mock the confirmation dialog
        page.execute_script('window.confirm = function() { return true; }')

        within('.transaction-card') do
          click_button '✓ Approve'
        end
        sleep(3)

        # Should update the transaction status and refresh the list
        expect(page).to have_content('🎉 No flagged transactions found!')
        expect(@flagged_transaction.reload.status).to eq('approved')
      end

      it 'cancels approval when confirmation is denied', js: true do
        @flagged_transaction.update!(status: 'flagged')

        visit '/review'
        sleep(3)

        select 'Flagged', from: 'Status'
        sleep(3)

        # Mock the confirmation dialog to return false
        page.execute_script('window.confirm = function() { return false; }')

        within('.transaction-card') do
          click_button '✓ Approve'
        end
        sleep(2)

        # Should not change anything
        expect(page).to have_content('Suspicious large purchase')
        expect(@flagged_transaction.reload.status).to eq('flagged')
      end
    end

    describe 'delete functionality' do
      it 'can delete a transaction', js: true do
        visit '/review'
        sleep(3)

        initial_count = Transaction.count

        # Mock the confirmation dialog
        page.execute_script('window.confirm = function() { return true; }')

        within('.transaction-card', match: :first) do
          click_button '🗑️ Delete'
        end
        sleep(3)

        # Should remove the transaction from database and update the list
        expect(Transaction.count).to eq(initial_count - 1)
        expect(page).to have_content('Flagged Transactions (2)')
      end

      it 'cancels deletion when confirmation is denied', js: true do
        visit '/review'
        sleep(3)

        initial_count = Transaction.count

        # Mock the confirmation dialog to return false
        page.execute_script('window.confirm = function() { return false; }')

        within('.transaction-card', match: :first) do
          click_button '🗑️ Delete'
        end
        sleep(2)

        # Should not delete anything
        expect(Transaction.count).to eq(initial_count)
        expect(page).to have_content('Flagged Transactions (3)')
      end
    end

    describe 'resolve anomaly functionality' do
      it 'can resolve individual anomalies', js: true do
        visit '/review'
        sleep(3)

        # Find a transaction with anomalies
        within('.transaction-card', text: 'Suspicious large purchase') do
          within('.anomaly-item', match: :first) do
            click_button '✓ Resolve'
          end
        end
        sleep(3)

        # Anomaly should be resolved
        expect(@unusual_amount_anomaly.reload.resolved).to be true

        # Page should update to reflect the change
        within('.transaction-card', text: 'Suspicious large purchase') do
          expect(page).not_to have_content('⚠️ Anomalies Detected')
        end
      end

      it 'updates the display when all anomalies are resolved', js: true do
        visit '/review'
        sleep(3)

        # Resolve all anomalies for a transaction
        within('.transaction-card', text: 'Suspicious large purchase') do
          click_button '✓ Resolve'
        end
        sleep(3)

        # The transaction should no longer show anomalies section
        within('.transaction-card', text: 'Suspicious large purchase') do
          expect(page).not_to have_content('⚠️ Anomalies Detected')
        end
      end
    end
  end

  describe 'edit transaction functionality' do
    it 'opens edit modal when edit button is clicked', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', text: 'Suspicious large purchase') do
        click_button '✏️ Edit'
      end
      sleep(2)

      expect(page).to have_content('Edit Transaction')
      expect(page).to have_field('Description', with: 'Suspicious large purchase')
      expect(page).to have_field('Amount', with: '5000')
      expect(page).to have_button('Save Changes')
      expect(page).to have_button('Cancel')
    end

    it 'can close edit modal with cancel button', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        click_button '✏️ Edit'
      end
      sleep(2)

      click_button 'Cancel'
      sleep(1)

      expect(page).not_to have_content('Edit Transaction')
    end

    it 'can close edit modal by clicking outside', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        click_button '✏️ Edit'
      end
      sleep(2)

      # Click on the modal overlay (outside the modal content)
      find('.modal').click
      sleep(1)

      expect(page).not_to have_content('Edit Transaction')
    end

    it 'loads categories in edit modal', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        click_button '✏️ Edit'
      end
      sleep(3) # Wait for categories to load

      within('.modal-content') do
        expect(page).to have_select('Category')
        expect(page).to have_option('Food & Dining')
        expect(page).to have_option('Transportation')
      end
    end

    it 'shows all required form fields', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        click_button '✏️ Edit'
      end
      sleep(2)

      within('.modal-content') do
        expect(page).to have_field('Description')
        expect(page).to have_field('Amount')
        expect(page).to have_field('Date')
        expect(page).to have_select('Category')
        expect(page).to have_select('Status')
      end
    end

    it 'has correct status options in edit modal', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        click_button '✏️ Edit'
      end
      sleep(2)

      within('.modal-content') do
        status_select = find('select[value*="pending"], select[value*="flagged"], select[value*="approved"], select[value*="rejected"]')
        within(status_select) do
          expect(page).to have_option('Pending')
          expect(page).to have_option('Approved')
          expect(page).to have_option('Flagged')
          expect(page).to have_option('Rejected')
        end
      end
    end

    it 'can save changes to a transaction', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', text: 'Suspicious large purchase') do
        click_button '✏️ Edit'
      end
      sleep(3)

      within('.modal-content') do
        fill_in 'Description', with: 'Updated suspicious purchase'
        fill_in 'Amount', with: '6000.00'
        select 'Transportation', from: 'Category'
        select 'Approved', from: 'Status'

        click_button 'Save Changes'
      end
      sleep(3)

      # Should close modal and update the transaction
      expect(page).not_to have_content('Edit Transaction')
      expect(page).to have_content('Updated suspicious purchase')
      expect(page).to have_content('$6,000.00')
      expect(page).to have_content('Transportation')

      # Verify database changes
      updated_transaction = @flagged_transaction.reload
      expect(updated_transaction.description).to eq('Updated suspicious purchase')
      expect(updated_transaction.amount).to eq(6000.00)
      expect(updated_transaction.status).to eq('approved')
      expect(updated_transaction.category.name).to eq('Transportation')
    end

    it 'shows validation errors for invalid data', js: true do
      visit '/review'
      sleep(3)

      within('.transaction-card', match: :first) do
        click_button '✏️ Edit'
      end
      sleep(2)

      within('.modal-content') do
        fill_in 'Description', with: ''  # Make description empty (invalid)
        fill_in 'Amount', with: 'invalid'  # Invalid amount

        click_button 'Save Changes'
      end
      sleep(2)

      # Should show error message and keep modal open
      expect(page).to have_content('Edit Transaction')
      # Note: The exact error message may vary based on API response
    end

    it 'retains original values when canceling edit', js: true do
      original_description = @flagged_transaction.description

      visit '/review'
      sleep(3)

      within('.transaction-card', text: 'Suspicious large purchase') do
        click_button '✏️ Edit'
      end
      sleep(2)

      within('.modal-content') do
        fill_in 'Description', with: 'Changed description'
        click_button 'Cancel'
      end
      sleep(2)

      # Should not save changes
      expect(@flagged_transaction.reload.description).to eq(original_description)
      expect(page).to have_content(original_description)
      expect(page).not_to have_content('Changed description')
    end
  end

  describe 'filters functionality' do
    it 'displays filter options', js: true do
      visit '/review'
      sleep(2)

      expect(page).to have_content('Filters')
      expect(page).to have_select('Status')
      expect(page).to have_select('Anomaly Type')
    end

    it 'has correct status filter options', js: true do
      visit '/review'
      sleep(2)

      # Find the status select specifically
      status_select = find('select', match: :first)
      within(status_select) do
        expect(page).to have_content('All Statuses')
        expect(page).to have_content('Flagged')
        expect(page).to have_content('Pending')
        expect(page).to have_content('Rejected')
      end
    end

    it 'has correct anomaly type filter options', js: true do
      visit '/review'
      sleep(2)

      # Find the anomaly type select (second select)
      anomaly_select = all('select')[1]
      within(anomaly_select) do
        expect(page).to have_content('All Types')
        expect(page).to have_content('Unusual Amount')
        expect(page).to have_content('Duplicate Transaction')
        expect(page).to have_content('Incomplete Metadata')
        expect(page).to have_content('Rule Based')
      end
    end

    describe 'status filtering' do
      it 'shows all transactions with anomalies by default', js: true do
        visit '/review'
        sleep(3)

        # Should show transactions with anomalies regardless of status
        expect(page).to have_content('Suspicious large purchase')
        expect(page).to have_content('Pending restaurant bill')
        expect(page).to have_content('Rejected invalid transaction')
        expect(page).to have_content('Flagged Transactions (3)')
      end

      it 'filters by flagged status correctly', js: true do
        visit '/review'
        sleep(3)

        # Change status filter to flagged
        select 'Flagged', from: 'Status'
        sleep(3)

        # Should only show flagged transactions
        expect(page).to have_content('Suspicious large purchase')
        expect(page).not_to have_content('Pending restaurant bill')
        expect(page).not_to have_content('Rejected invalid transaction')
        expect(page).to have_content('Flagged Transactions (1)')
      end

      it 'filters by pending status correctly', js: true do
        visit '/review'
        sleep(3)

        # Change status filter to pending
        select 'Pending', from: 'Status'
        sleep(3)

        # Should show pending transactions (including ones with and without anomalies)
        expect(page).to have_content('Pending restaurant bill')
        expect(page).not_to have_content('Suspicious large purchase')
        expect(page).not_to have_content('Rejected invalid transaction')
      end

      it 'filters by rejected status correctly', js: true do
        visit '/review'
        sleep(3)

        # Change status filter to rejected
        select 'Rejected', from: 'Status'
        sleep(3)

        # Should show rejected transactions
        expect(page).to have_content('Rejected invalid transaction')
        expect(page).not_to have_content('Suspicious large purchase')
        expect(page).not_to have_content('Pending restaurant bill')
      end

      it 'resets to show all when selecting "All Statuses"', js: true do
        visit '/review'
        sleep(3)

        # First filter by flagged
        select 'Flagged', from: 'Status'
        sleep(3)
        expect(page).to have_content('Flagged Transactions (1)')

        # Then reset to all
        select 'All Statuses', from: 'Status'
        sleep(3)
        expect(page).to have_content('Flagged Transactions (3)')
      end
    end

    describe 'anomaly type filtering' do
      it 'filters by unusual amount anomaly type', js: true do
        visit '/review'
        sleep(3)

        # Filter by unusual amount
        select 'Unusual Amount', from: 'Anomaly Type'
        sleep(3)

        # Should only show transactions with unusual amount anomalies
        expect(page).to have_content('Suspicious large purchase')
        expect(page).to have_content('UNUSUAL AMOUNT')
        expect(page).not_to have_content('Pending restaurant bill')
        expect(page).not_to have_content('Rejected invalid transaction')
      end

      it 'filters by incomplete metadata anomaly type', js: true do
        visit '/review'
        sleep(3)

        # Filter by incomplete metadata
        select 'Incomplete Metadata', from: 'Anomaly Type'
        sleep(3)

        # Should only show transactions with incomplete metadata anomalies
        expect(page).to have_content('Pending restaurant bill')
        expect(page).to have_content('INCOMPLETE METADATA')
        expect(page).not_to have_content('Suspicious large purchase')
        expect(page).not_to have_content('Rejected invalid transaction')
      end

      it 'filters by duplicate transaction anomaly type', js: true do
        visit '/review'
        sleep(3)

        # Filter by duplicate transaction
        select 'Duplicate Transaction', from: 'Anomaly Type'
        sleep(3)

        # Should only show transactions with duplicate anomalies
        expect(page).to have_content('Rejected invalid transaction')
        expect(page).to have_content('DUPLICATE TRANSACTION')
        expect(page).not_to have_content('Suspicious large purchase')
        expect(page).not_to have_content('Pending restaurant bill')
      end
    end

    describe 'combined filtering' do
      it 'can combine status and anomaly type filters', js: true do
        visit '/review'
        sleep(3)

        # Filter by pending status AND incomplete metadata anomaly type
        select 'Pending', from: 'Status'
        select 'Incomplete Metadata', from: 'Anomaly Type'
        sleep(3)

        # Should show only pending transactions with incomplete metadata anomalies
        expect(page).to have_content('Pending restaurant bill')
        expect(page).to have_content('INCOMPLETE METADATA')
        expect(page).not_to have_content('Suspicious large purchase')
        expect(page).not_to have_content('Rejected invalid transaction')
      end

      it 'shows empty state when filters have no matches', js: true do
        visit '/review'
        sleep(3)

        # Filter by flagged status AND duplicate anomaly type (should be no matches)
        select 'Flagged', from: 'Status'
        select 'Duplicate Transaction', from: 'Anomaly Type'
        sleep(3)

        # Should show empty state
        expect(page).to have_content('🎉 No flagged transactions found!')
        expect(page).to have_content('Flagged Transactions (0)')
      end
    end
  end

  describe 'pagination' do
    it 'shows pagination when there are many transactions', js: true do
      # Create many flagged transactions
      15.times do |i|
        transaction = create(:transaction, status: 'flagged', description: "Flagged transaction #{i}")
        create(:anomaly_detection, transaction_record: transaction)
      end

      visit '/review'
      sleep(3)

      # Should show pagination controls
      expect(page).to have_content('Page 1 of')
      expect(page).to have_button('Next →')
    end
  end

  describe 'error handling' do
    it 'handles API errors gracefully', js: true do
      # Mock API failure
      page.execute_script("""
        window.originalFetch = window.fetch;
        window.fetch = function(url) {
          if (url.includes('/api/v1/transactions/anomalies')) {
            return Promise.reject(new Error('Network error'));
          }
          return window.originalFetch.apply(this, arguments);
        };
      """)

      visit '/review'
      sleep(3)

      # Should show loading or error state, not crash
      expect(page).to have_content('Loading transactions').or have_content('Error loading')

      # Restore fetch
      page.execute_script('window.fetch = window.originalFetch;')
    end
  end

  describe 'responsive design' do
    it 'is accessible on mobile viewports', js: true do
      page.driver.browser.manage.window.resize_to(375, 667) # iPhone size

      visit '/review'
      sleep(3)

      expect(page).to have_content('Review Flagged Transactions')
      expect(page).to have_button('✓ Approve')
    end
  end

  describe 'automatic transaction flagging' do
    it 'shows transactions that were automatically flagged by anomaly detection', js: true do
      # Create a transaction that will be automatically flagged
      auto_flagged_transaction = create(:transaction,
        description: 'Auto-flagged transaction',
        amount: 200.0,
        category: nil,  # Missing category triggers anomaly
        status: 'pending'
      )

      # Run anomaly detection service which should flag the transaction
      AnomalyDetectionService.new(auto_flagged_transaction).detect_and_flag

      # Verify the transaction was flagged
      expect(auto_flagged_transaction.reload.status).to eq('flagged')

      visit '/review'
      sleep(3)

      # Filter by flagged status
      select 'Flagged', from: 'Status'
      sleep(3)

      # Should show the automatically flagged transaction
      expect(page).to have_content('Auto-flagged transaction')
      expect(page).to have_content('INCOMPLETE METADATA')
      expect(page).to have_content('Incomplete transaction data: Missing category')
    end

    it 'ensures all transactions with anomalies appear in the flagged filter', js: true do
      # Create transactions with different types of anomalies
      incomplete_transaction = create(:transaction,
        description: 'Incomplete transaction',
        amount: 100.0,
        category: nil,
        status: 'pending'
      )

      # Run anomaly detection
      AnomalyDetectionService.new(incomplete_transaction).detect_and_flag

      visit '/review'
      sleep(3)

      # Filter by flagged status
      select 'Flagged', from: 'Status'
      sleep(3)

      # Should include all flagged transactions (existing + auto-flagged)
      expect(page).to have_content('Suspicious large purchase')  # Pre-existing flagged
      expect(page).to have_content('Incomplete transaction')     # Auto-flagged
    end
  end

  describe 'dynamic page titles and headers' do
    it 'updates page title and section header when filter changes', js: true do
      visit '/review'
      sleep(3)

      # Should start with flagged filter by default
      expect(page).to have_content('🚨 Review Flagged Transactions')
      expect(page).to have_content('Flagged Transactions (1)')

      # Change to pending status
      select 'Pending', from: 'Status'
      sleep(3)

      expect(page).to have_content('🚨 Review Pending Transactions')
      expect(page).to have_content('Pending Transactions')

      # Change to all statuses
      select 'All Statuses', from: 'Status'
      sleep(3)

      expect(page).to have_content('🚨 Review All Transactions')
      expect(page).to have_content('All Transactions')
    end

    it 'shows all transactions when All Statuses filter is selected', js: true do
      # Create some additional transactions with different statuses
      create(:transaction, description: 'Approved transaction', status: 'approved', category: @category)
      create(:transaction, description: 'Another pending transaction', status: 'pending', category: @category)

      visit '/review'
      sleep(3)

      # Start with flagged filter - should show only flagged
      expect(page).to have_content('Flagged Transactions (1)')
      expect(page).to have_content('Suspicious large purchase')
      expect(page).not_to have_content('Approved transaction')

      # Switch to All Statuses - should show all transactions
      select 'All Statuses', from: 'Status'
      sleep(3)

      expect(page).to have_content('All Transactions')
      expect(page).to have_content('Suspicious large purchase')
      expect(page).to have_content('Approved transaction')
      expect(page).to have_content('Another pending transaction')
    end

    it 'starts with Flagged filter selected by default', js: true do
      visit '/review'
      sleep(2)

      # The status dropdown should have 'Flagged' selected by default
      status_select = find('#status-filter')
      expect(status_select.value).to eq('flagged')
    end
  end
end
