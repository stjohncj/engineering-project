require 'rails_helper'

RSpec.describe 'Rules Management', type: :system do
  before do
    driven_by(:selenium_chrome_headless)
    # Clean up any remaining data to prevent test contamination
    AnomalyDetection.delete_all
    Transaction.delete_all
    Category.delete_all
    Rule.delete_all

    # Create test categories
    @category1 = create(:category, name: 'Food & Dining')
    @category2 = create(:category, name: 'Transportation')
  end

  describe 'rules page access' do
    it 'is accessible from the main URL', js: true do
      visit '/rules'
      sleep(2)

      expect(page).to have_content('Rules Management')
      expect(page).to have_content('Create and manage rules to automatically categorize and flag transactions')
    end

    it 'shows empty state when no rules exist', js: true do
      visit '/rules'
      sleep(3)

      expect(page).to have_content('Rules (0)')
      expect(page).to have_content('No rules configured')
      expect(page).to have_button('+ Create Rule')
    end

    it 'has navigation back to dashboard', js: true do
      visit '/rules'
      sleep(2)

      expect(page).to have_link('← Back to Dashboard', href: '/')
    end
  end

  describe 'rule creation' do
    it 'opens create rule modal when create button is clicked', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      expect(page).to have_content('Create New Rule')
      expect(page).to have_field('Rule Name')
      expect(page).to have_field('If Field')
      expect(page).to have_field('Condition')
      expect(page).to have_field('Value')
      expect(page).to have_field('Then Action')
      expect(page).to have_field('Action Value')
    end

    it 'creates a new categorization rule', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      fill_in 'Rule Name', with: 'Amazon Shopping Rule'
      select 'Description', from: 'If Field'
      select 'Contains', from: 'Condition'
      fill_in 'Value', with: 'Amazon'
      select 'Categorize as', from: 'Then Action'
      fill_in 'Action Value', with: 'Shopping'

      click_button 'Create Rule'
      sleep(3)

      expect(page).to have_content('Amazon Shopping Rule')
      expect(page).to have_content('description contains "Amazon"')
      expect(page).to have_content('categorize as "Shopping"')
      expect(page).to have_content('Active')
    end

    it 'creates a new flagging rule', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      fill_in 'Rule Name', with: 'High Value Transaction Rule'
      select 'Amount', from: 'If Field'
      select 'Greater than', from: 'Condition'
      fill_in 'Value', with: '1000'
      select 'Flag as', from: 'Then Action'
      fill_in 'Action Value', with: 'High Value'

      click_button 'Create Rule'
      sleep(3)

      expect(page).to have_content('High Value Transaction Rule')
      expect(page).to have_content('amount greater than "1000"')
      expect(page).to have_content('flag as "High Value"')
    end

    it 'shows validation errors for invalid input', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      # Try to create without required fields
      click_button 'Create Rule'
      sleep(2)

      # The form should still be open and show validation errors
      expect(page).to have_content('Create New Rule')
    end

    it 'cancels rule creation', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      fill_in 'Rule Name', with: 'Test Rule'
      click_button 'Cancel'
      sleep(1)

      expect(page).not_to have_content('Create New Rule')
      expect(page).not_to have_content('Test Rule')
    end
  end

  describe 'rule management with existing rules' do
    def setup_rules
      @rule1 = create(:rule,
        name: 'Amazon Categorization',
        condition_field: 'description',
        condition_operator: 'contains',
        condition_value: 'Amazon',
        action_type: 'categorize',
        action_value: 'Shopping',
        active: true
      )

      @rule2 = create(:rule,
        name: 'High Value Flagging',
        condition_field: 'amount',
        condition_operator: 'greater_than',
        condition_value: '1000',
        action_type: 'flag',
        action_value: 'High Value',
        active: false
      )
    end

    it 'displays existing rules', js: true do
      setup_rules
      visit '/rules'
      sleep(3)

      expect(page).to have_content('Rules (2)')
      expect(page).to have_content('Amazon Categorization')
      expect(page).to have_content('High Value Flagging')

      # Check rule details
      expect(page).to have_content('description contains "Amazon"')
      expect(page).to have_content('categorize as "Shopping"')
      expect(page).to have_content('amount greater than "1000"')
      expect(page).to have_content('flag as "High Value"')
    end

    it 'shows correct active/inactive status', js: true do
      setup_rules
      visit '/rules'
      sleep(3)

      # Find the Amazon rule card and check it's active
      amazon_card = find('.rule-card', text: 'Amazon Categorization')
      within(amazon_card) do
        expect(page).to have_content('Active')
        expect(page).to have_button('Deactivate')
      end

      # Find the High Value rule card and check it's inactive
      high_value_card = find('.rule-card', text: 'High Value Flagging')
      within(high_value_card) do
        expect(page).to have_content('Inactive')
        expect(page).to have_button('Activate')
      end
    end

    it 'can toggle rule active status', js: true do
      setup_rules
      visit '/rules'
      sleep(3)

      # Deactivate the active rule
      amazon_card = find('.rule-card', text: 'Amazon Categorization')
      within(amazon_card) do
        click_button 'Deactivate'
      end
      sleep(2)

      # Check it's now inactive
      within(amazon_card) do
        expect(page).to have_content('Inactive')
        expect(page).to have_button('Activate')
      end
    end

    it 'can edit an existing rule', js: true do
      setup_rules
      visit '/rules'
      sleep(3)

      amazon_card = find('.rule-card', text: 'Amazon Categorization')
      within(amazon_card) do
        click_button 'Edit'
      end
      sleep(1)

      expect(page).to have_content('Edit Rule')
      expect(page).to have_field('Rule Name', with: 'Amazon Categorization')

      fill_in 'Rule Name', with: 'Updated Amazon Rule'
      click_button 'Update Rule'
      sleep(3)

      expect(page).to have_content('Updated Amazon Rule')
      expect(page).not_to have_content('Amazon Categorization')
    end

    it 'can delete a rule', js: true do
      setup_rules
      visit '/rules'
      sleep(3)

      expect(page).to have_content('Rules (2)')

      amazon_card = find('.rule-card', text: 'Amazon Categorization')
      within(amazon_card) do
        accept_confirm do
          click_button 'Delete'
        end
      end
      sleep(2)

      expect(page).not_to have_content('Amazon Categorization')
      expect(page).to have_content('Rules (1)')
    end

    it 'shows confirmation dialog before deleting', js: true do
      setup_rules
      visit '/rules'
      sleep(3)

      amazon_card = find('.rule-card', text: 'Amazon Categorization')
      within(amazon_card) do
        dismiss_confirm do
          click_button 'Delete'
        end
      end
      sleep(1)

      # Rule should still be there
      expect(page).to have_content('Amazon Categorization')
      expect(page).to have_content('Rules (2)')
    end
  end

  describe 'form validation and user experience' do
    it 'shows helpful placeholders and examples', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      expect(page).to have_content('Example Rules:')
      expect(page).to have_content('Description contains "Amazon" → Categorize as "Shopping"')
      expect(page).to have_content('Amount greater than 1000 → Flag as "High Value"')
    end

    it 'updates placeholder text based on field selection', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      # Check description field placeholder
      select 'Description', from: 'If Field'
      value_field = find('#condition-value')
      expect(value_field['placeholder']).to include('Amazon')

      # Check amount field placeholder
      select 'Amount', from: 'If Field'
      sleep(1)
      expect(value_field['placeholder']).to include('1000')
    end

    it 'updates action placeholder based on action type', js: true do
      visit '/rules'
      sleep(2)

      click_button '+ Create Rule'
      sleep(1)

      action_value_field = find('#action-value')

      # Check categorize placeholder
      select 'Categorize as', from: 'Then Action'
      expect(action_value_field['placeholder']).to include('Shopping')

      # Check flag placeholder
      select 'Flag as', from: 'Then Action'
      sleep(1)
      expect(action_value_field['placeholder']).to include('High Value')
    end
  end

  describe 'responsive design' do
    it 'works on smaller screens', js: true do
      page.driver.browser.manage.window.resize_to(768, 1024)

      visit '/rules'
      sleep(3)

      expect(page).to have_content('Rules Management')
      expect(page).to have_button('+ Create Rule')

      # Should still be functional
      click_button '+ Create Rule'
      sleep(1)
      expect(page).to have_content('Create New Rule')
    end
  end
end
