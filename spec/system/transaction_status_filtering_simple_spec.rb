require 'rails_helper'

RSpec.describe 'Transaction Status Filtering Simple Test', type: :system do
  before(:each) do
    driven_by(:selenium_chrome_headless)
    # Clean the database before each test
    Transaction.destroy_all
    Category.destroy_all
    AnomalyDetection.destroy_all
  end

  it 'removes approved transaction from flagged filter view', js: true do
    # Create test data
    category = Category.create!(name: 'Test Category')

    # Create flagged transactions
    flagged1 = Transaction.create!(
      description: 'Flagged Transaction 1',
      amount: 1000.00,
      status: 'flagged',
      category: category,
      transaction_date: Date.today
    )

    flagged2 = Transaction.create!(
      description: 'Flagged Transaction 2',
      amount: 2000.00,
      status: 'flagged',
      category: category,
      transaction_date: Date.today
    )

    # Create anomalies so they show up in the review page
    AnomalyDetection.create!(
      transaction_record: flagged1,
      anomaly_type: 'unusual_amount',
      severity: 4,
      description: 'High amount'
    )

    AnomalyDetection.create!(
      transaction_record: flagged2,
      anomaly_type: 'unusual_amount',
      severity: 3,
      description: 'Medium high amount'
    )

    # Visit review page
    visit '/review'
    sleep(3)

    # Verify both transactions are visible
    expect(page).to have_content('Flagged Transaction 1')
    expect(page).to have_content('Flagged Transaction 2')
    expect(page).to have_content('$1,000.00')
    expect(page).to have_content('$2,000.00')

    # Count initial transactions
    initial_count = all('.transaction-card').count
    expect(initial_count).to eq(2)

    # Approve the first transaction (which will be Flagged Transaction 2 due to date ordering)
    within(first('.transaction-card')) do
      accept_confirm do
        click_button '✓ Approve'
      end
    end

    # Wait for UI update
    sleep(2)

    # Since we approved one transaction, we should only see one remaining
    # We need to check which one was approved based on what's left
    remaining_count = all('.transaction-card').count
    expect(remaining_count).to eq(1)

    # One of the transactions should be gone, one should remain
    page_text = page.text
    has_transaction_1 = page_text.include?('Flagged Transaction 1')
    has_transaction_2 = page_text.include?('Flagged Transaction 2')

    # Exactly one should be visible
    expect(has_transaction_1 ^ has_transaction_2).to be true

    # Verify count decreased
    updated_count = all('.transaction-card').count
    expect(updated_count).to eq(1)

    # Verify at least one transaction was approved in the database
    approved_count = Transaction.where(status: 'approved').count
    flagged_count = Transaction.where(status: 'flagged').count
    expect(approved_count).to eq(1)
    expect(flagged_count).to eq(1)
  end

  it 'updates transaction display when edited and still matches filter', js: true do
    # Create test data
    category = Category.create!(name: 'Test Category')

    transaction = Transaction.create!(
      description: 'Original Description',
      amount: 500.00,
      status: 'flagged',
      category: category,
      transaction_date: Date.today
    )

    AnomalyDetection.create!(
      transaction_record: transaction,
      anomaly_type: 'unusual_amount',
      severity: 3,
      description: 'Test anomaly'
    )

    visit '/review'
    sleep(3)

    expect(page).to have_content('Original Description')

    # Edit the transaction
    within('.transaction-card') do
      click_button '✏️ Edit'
    end

    sleep(1)

    # Change description but keep status as flagged
    within('.modal-content') do
      fill_in 'edit-description', with: 'Updated Description'
      select 'Flagged', from: 'edit-status'
      click_button 'Save Changes'
    end

    sleep(2)

    # Verify the updated description is visible
    expect(page).to have_content('Updated Description')
    expect(page).not_to have_content('Original Description')

    # Transaction should still be in the list
    expect(all('.transaction-card').count).to eq(1)

    # Verify database was updated
    transaction.reload
    expect(transaction.description).to eq('Updated Description')
    expect(transaction.status).to eq('flagged')
  end

  it 'removes transaction when status changed to non-matching filter', js: true do
    # Create test data
    category = Category.create!(name: 'Test Category')

    transaction = Transaction.create!(
      description: 'Test Transaction',
      amount: 750.00,
      status: 'flagged',
      category: category,
      transaction_date: Date.today
    )

    AnomalyDetection.create!(
      transaction_record: transaction,
      anomaly_type: 'unusual_amount',
      severity: 3,
      description: 'Test anomaly'
    )

    visit '/review'
    sleep(3)

    expect(page).to have_content('Test Transaction')

    # Edit and change status
    within('.transaction-card') do
      click_button '✏️ Edit'
    end

    sleep(1)

    within('.modal-content') do
      select 'Approved', from: 'edit-status'
      click_button 'Save Changes'
    end

    sleep(2)

    # Transaction should be removed from view
    expect(page).not_to have_content('Test Transaction')

    # Should show empty state
    expect(page).to have_content('No flagged transactions found!')

    # Verify database was updated
    transaction.reload
    expect(transaction.status).to eq('approved')
  end
end
