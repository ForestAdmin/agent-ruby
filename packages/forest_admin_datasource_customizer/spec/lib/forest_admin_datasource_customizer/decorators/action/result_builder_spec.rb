require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query

      describe ResultBuilder do
        subject(:result_builder) { described_class.new }

        it 'return a result with header' do
          expect(result_builder.set_header('header_key', 'header_value').success).to eq(
            {
              headers: { 'header_key' => 'header_value' },
              type: 'Success',
              message: 'Success',
              refresh: { relationships: [] },
              html: nil
            }
          )
        end

        it 'return a success result' do
          expect(result_builder.success).to eq(
            {
              headers: {},
              type: 'Success',
              message: 'Success',
              refresh: { relationships: [] },
              html: nil
            }
          )

          expect(result_builder.success(message: 'foo', options: { html: '<div>That worked!</div>' })).to eq(
            {
              headers: {},
              type: 'Success',
              message: 'foo',
              refresh: { relationships: [] },
              html: '<div>That worked!</div>'
            }
          )
        end

        it 'return an error result' do
          expect(result_builder.error).to eq(
            {
              headers: {},
              type: 'Error',
              message: 'Error',
              status: 400,
              html: nil
            }
          )

          expect(result_builder.error(message: 'foo', options: { html: '<div>That worked!</div>' })).to eq(
            {
              headers: {},
              type: 'Error',
              message: 'foo',
              status: 400,
              html: '<div>That worked!</div>'
            }
          )
        end

        it 'return a file result' do
          expect(result_builder.file(content: 'col1,col2,col3', name: 'test.csv', mime_type: 'text/csv')).to eq(
            {
              headers: {},
              type: 'File',
              name: 'test.csv',
              mime_type: 'text/csv',
              stream: 'col1,col2,col3'
            }
          )
        end

        it 'return a webhook result' do
          expect(result_builder.webhook(url: 'http://someurl')).to eq(
            {
              headers: {},
              type: 'Webhook',
              webhook: {
                body: {},
                headers: {},
                method: 'POST',
                url: 'http://someurl'
              }
            }
          )
        end

        it 'return a redirect result' do
          expect(result_builder.redirect_to(path: '/mypath')).to eq(
            {
              headers: {},
              type: 'Redirect',
              redirect_to: '/mypath'
            }
          )
        end
      end
    end
  end
end
