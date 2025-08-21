require 'rails_helper'

RSpec.describe BulkRuleApplicationJob, type: :job do
  include ActiveJob::TestHelper

  let(:category) { create(:category) }
  let!(:transactions) { create_list(:transaction, 3, category: category) }
  let(:transaction_ids) { transactions.map(&:id) }

  let!(:active_rule) { create(:rule, active: true) }
  let!(:inactive_rule) { create(:rule, active: false) }

  describe '#perform' do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    it 'applies active rules to all specified transactions' do
      expect(active_rule).to receive(:apply_to!).exactly(3).times
      expect(inactive_rule).not_to receive(:apply_to!)

      described_class.perform_now(transaction_ids)
    end

    it 'processes transactions in batches' do
      # Create more transactions to test batching
      additional_transactions = create_list(:transaction, 150, category: category)
      all_transaction_ids = transaction_ids + additional_transactions.map(&:id)

      expect(Transaction).to receive(:includes).with(:category).and_call_original
      expect_any_instance_of(ActiveRecord::Relation).to receive(:find_in_batches).with(batch_size: 100).and_call_original

      described_class.perform_now(all_transaction_ids)
    end

    it 'logs successful completion' do
      expect(Rails.logger).to receive(:info).with(/BulkRuleApplicationJob: Applied rules to \d+ transactions/)

      described_class.perform_now(transaction_ids)
    end

    it 'invalidates transaction-related caches' do
      expect(Rails.cache).to receive(:delete).with("dashboard_statistics")
      expect(Rails.cache).to receive(:delete).with("recent_transactions")
      expect(Rails.cache).to receive(:delete).with("category_breakdown")
      expect(Rails.cache).to receive(:delete_matched).with("transactions_index_*")

      described_class.perform_now(transaction_ids)
    end

    context 'when specific rule IDs are provided' do
      let(:rule_ids) { [ active_rule.id ] }

      it 'only applies the specified rules' do
        expect(active_rule).to receive(:apply_to!).exactly(3).times
        expect(inactive_rule).not_to receive(:apply_to!)

        described_class.perform_now(transaction_ids, rule_ids)
      end
    end

    context 'when a rule application fails' do
      before do
        allow(active_rule).to receive(:apply_to!).and_raise(StandardError, "Rule application failed")
      end

      it 'logs the error and continues with other transactions' do
        expect(Rails.logger).to receive(:error).exactly(3).times do |message|
          expect(message).to match(/Failed to apply rule #{active_rule.id} to transaction \d+: Rule application failed/)
        end

        expect { described_class.perform_now(transaction_ids) }.not_to raise_error
      end
    end

    context 'when the job itself fails' do
      before do
        allow(Transaction).to receive(:includes).and_raise(StandardError, "Database connection failed")
      end

      it 'logs the error and re-raises it' do
        expect(Rails.logger).to receive(:error).with("BulkRuleApplicationJob failed: Database connection failed")

        expect { described_class.perform_now(transaction_ids) }.to raise_error(StandardError, "Database connection failed")
      end
    end
  end

  describe 'job configuration' do
    it 'is queued on the default queue' do
      expect(described_class.queue_name).to eq('default')
    end

    it 'retries on StandardError with exponential backoff' do
      expect(described_class.retry_on).to include(StandardError)
    end
  end

  describe 'job enqueueing' do
    it 'enqueues the job correctly' do
      expect {
        described_class.perform_later(transaction_ids)
      }.to enqueue_job(described_class).with(transaction_ids).on_queue('default')
    end

    it 'enqueues the job with rule IDs' do
      rule_ids = [ active_rule.id ]

      expect {
        described_class.perform_later(transaction_ids, rule_ids)
      }.to enqueue_job(described_class).with(transaction_ids, rule_ids).on_queue('default')
    end
  end
end
