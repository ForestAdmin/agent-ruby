# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubleReference

require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module DSL
    describe ExecutionContext do
      let(:context) { instance_spy('ExecutionContextDelegate') }
      let(:result_builder) { instance_spy('ResultBuilder') }
      let(:execution_context) { described_class.new(context, result_builder) }

      describe '#form_value' do
        it 'delegates to context.get_form_value with string key' do
          allow(context).to receive(:get_form_value).with('email').and_return('test@example.com')

          result = execution_context.form_value(:email)
          expect(context).to have_received(:get_form_value).with('email')
          expect(result).to eq('test@example.com')
        end

        it 'converts symbol to string' do
          allow(context).to receive(:get_form_value).with('field_name').and_return('value')

          execution_context.form_value(:field_name)
          expect(context).to have_received(:get_form_value).with('field_name')
        end
      end

      describe '#record' do
        it 'delegates to context.get_record' do
          record_data = { 'id' => 1, 'name' => 'Test' }
          allow(context).to receive(:get_record).with(['id', 'name']).and_return(record_data)

          result = execution_context.record(['id', 'name'])
          expect(context).to have_received(:get_record).with(['id', 'name'])
          expect(result).to eq(record_data)
        end

        it 'works with empty fields array' do
          record_data = { 'id' => 1 }
          allow(context).to receive(:get_record).with([]).and_return(record_data)

          result = execution_context.record([])
          expect(context).to have_received(:get_record).with([])
          expect(result).to eq(record_data)
        end
      end

      describe '#records' do
        it 'delegates to context.get_records' do
          records_data = [{ 'id' => 1 }, { 'id' => 2 }]
          allow(context).to receive(:get_records).with(['id']).and_return(records_data)

          result = execution_context.records(['id'])
          expect(context).to have_received(:get_records).with(['id'])
          expect(result).to eq(records_data)
        end

        it 'works with empty fields array' do
          records_data = [{ 'id' => 1 }]
          allow(context).to receive(:get_records).with([]).and_return(records_data)

          result = execution_context.records([])
          expect(context).to have_received(:get_records).with([])
          expect(result).to eq(records_data)
        end
      end

      describe '#datasource' do
        it 'delegates to context' do
          datasource = instance_spy('Datasource')
          allow(context).to receive(:datasource).and_return(datasource)

          result = execution_context.datasource
          expect(context).to have_received(:datasource)
          expect(result).to eq(datasource)
        end
      end

      describe '#caller' do
        it 'delegates to context' do
          caller_obj = instance_spy('Caller')
          allow(context).to receive(:caller).and_return(caller_obj)

          result = execution_context.caller
          expect(context).to have_received(:caller)
          expect(result).to eq(caller_obj)
        end
      end

      describe '#success' do
        it 'returns success result with default message' do
          expected_result = { type: 'Success', message: 'Success' }
          allow(result_builder).to receive(:success).with(
            message: 'Success',
            options: {}
          ).and_return(expected_result)

          result = execution_context.success
          expect(result).to eq(expected_result)
          expect(execution_context.result).to eq(expected_result)
        end

        it 'returns success result with custom message' do
          expected_result = { type: 'Success', message: 'Operation completed' }
          allow(result_builder).to receive(:success).with(
            message: 'Operation completed',
            options: {}
          ).and_return(expected_result)

          execution_context.success('Operation completed')
          expect(result_builder).to have_received(:success)
        end

        it 'includes invalidated collections' do
          allow(result_builder).to receive(:success).with(
            message: 'Done',
            options: { invalidated: ['books', 'authors'] }
          )

          execution_context.success('Done', invalidated: %w[books authors])
          expect(result_builder).to have_received(:success)
        end

        it 'includes HTML content' do
          allow(result_builder).to receive(:success).with(
            message: 'Done',
            options: { html: '<p>Success</p>' }
          )

          execution_context.success('Done', html: '<p>Success</p>')
          expect(result_builder).to have_received(:success)
        end
      end

      describe '#error' do
        it 'returns error result with default message' do
          expected_result = { type: 'Error', message: 'Error' }
          allow(result_builder).to receive(:error).with(
            message: 'Error',
            options: {}
          ).and_return(expected_result)

          result = execution_context.error
          expect(result).to eq(expected_result)
          expect(execution_context.result).to eq(expected_result)
        end

        it 'returns error result with custom message' do
          expected_result = { type: 'Error', message: 'Operation failed' }
          allow(result_builder).to receive(:error).with(
            message: 'Operation failed',
            options: {}
          ).and_return(expected_result)

          execution_context.error('Operation failed')
          expect(result_builder).to have_received(:error)
        end

        it 'includes HTML content' do
          allow(result_builder).to receive(:error).with(
            message: 'Failed',
            options: { html: '<p>Error details</p>' }
          )

          execution_context.error('Failed', html: '<p>Error details</p>')
          expect(result_builder).to have_received(:error)
        end
      end

      describe '#file' do
        it 'returns file result' do
          expected_result = { type: 'File', content: 'data', name: 'export.csv' }
          allow(result_builder).to receive(:file).with(
            content: 'data',
            name: 'export.csv',
            mime_type: 'text/csv'
          ).and_return(expected_result)

          result = execution_context.file(
            content: 'data',
            name: 'export.csv',
            mime_type: 'text/csv'
          )
          expect(result).to eq(expected_result)
        end

        it 'uses default values' do
          allow(result_builder).to receive(:file).with(
            content: 'data',
            name: 'file',
            mime_type: 'application/octet-stream'
          )

          execution_context.file(content: 'data')
          expect(result_builder).to have_received(:file)
        end
      end

      describe '#webhook' do
        it 'returns webhook result' do
          expected_result = { type: 'Webhook', url: 'https://example.com/webhook' }
          allow(result_builder).to receive(:webhook).with(
            url: 'https://example.com/webhook',
            method: 'POST',
            headers: { 'Authorization' => 'Bearer token' },
            body: { data: 'value' }
          ).and_return(expected_result)

          result = execution_context.webhook(
            'https://example.com/webhook',
            method: 'POST',
            headers: { 'Authorization' => 'Bearer token' },
            body: { data: 'value' }
          )
          expect(result).to eq(expected_result)
        end

        it 'uses default method' do
          allow(result_builder).to receive(:webhook).with(
            url: 'https://example.com/webhook',
            method: 'POST',
            headers: {},
            body: {}
          )

          execution_context.webhook('https://example.com/webhook')
          expect(result_builder).to have_received(:webhook)
        end
      end

      describe '#redirect' do
        it 'returns redirect result' do
          expected_result = { type: 'Redirect', path: '/dashboard' }
          allow(result_builder).to receive(:redirect_to).with(
            path: '/dashboard'
          ).and_return(expected_result)

          result = execution_context.redirect('/dashboard')
          expect(result).to eq(expected_result)
        end
      end
    end
  end
end

# rubocop:enable RSpec/VerifiedDoubleReference
