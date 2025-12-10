# frozen_string_literal: true

# rubocop:disable Style/Semicolon

require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module DSL
    describe FormBuilder do
      describe '#field' do
        it 'adds a simple field' do
          builder = described_class.new
          builder.field :email, type: :string

          expect(builder.fields.length).to eq(1)
          expect(builder.fields[0][:label]).to eq('email')
          expect(builder.fields[0][:type]).to eq('String')
        end

        it 'normalizes type symbols' do
          type_mappings = {
            string: 'String',
            number: 'Number',
            integer: 'Number',
            boolean: 'Boolean',
            date: 'Date',
            datetime: 'Date',
            json: 'Json',
            file: 'File'
          }

          type_mappings.each do |symbol, expected|
            builder = described_class.new
            builder.field :test, type: symbol

            expect(builder.fields[0][:type]).to eq(expected)
          end
        end

        it 'adds field with widget' do
          builder = described_class.new
          builder.field :photo, type: :string, widget: 'FilePicker'

          field = builder.fields[0]
          expect(field[:widget]).to eq('FilePicker')
        end

        it 'adds field with options' do
          builder = described_class.new
          options = [
            { label: 'Option 1', value: '1' },
            { label: 'Option 2', value: '2' }
          ]
          builder.field :choice, type: :string, widget: 'Dropdown', options: options

          field = builder.fields[0]
          expect(field[:options]).to eq(options)
        end

        it 'adds readonly field' do
          builder = described_class.new
          builder.field :computed, type: :string, readonly: true

          field = builder.fields[0]
          expect(field[:is_read_only]).to be true
        end

        it 'adds field with default value' do
          builder = described_class.new
          builder.field :status, type: :string, default: 'pending'

          field = builder.fields[0]
          expect(field[:default_value]).to eq('pending')
        end

        it 'adds field with description' do
          builder = described_class.new
          builder.field :email, type: :string, description: 'User email address'

          field = builder.fields[0]
          expect(field[:description]).to eq('User email address')
        end

        it 'adds field with placeholder' do
          builder = described_class.new
          builder.field :email, type: :string, placeholder: 'Enter email...'

          field = builder.fields[0]
          expect(field[:placeholder]).to eq('Enter email...')
        end

        it 'adds computed field with block' do
          builder = described_class.new
          compute_block = proc { |context| context.form_value('other') }
          builder.field :computed, type: :string, readonly: true, &compute_block

          field = builder.fields[0]
          expect(field[:value]).to eq(compute_block)
        end

        it 'adds required field' do
          builder = described_class.new
          builder.field :email, type: :string, required: true

          field = builder.fields[0]
          expect(field[:is_required]).to be true
        end

        it 'adds field with dynamic required' do
          builder = described_class.new
          required_proc = proc { |ctx| ctx.get_form_value('amount').to_i > 1000 }
          builder.field :reason, type: :string, required: required_proc

          field = builder.fields[0]
          expect(field[:is_required]).to eq(required_proc)
        end

        it 'adds field with if_condition' do
          builder = described_class.new
          condition_proc = proc { |ctx| ctx.get_form_value('show_advanced') }
          builder.field :advanced_option, type: :string, if_condition: condition_proc

          field = builder.fields[0]
          expect(field[:if_condition]).to eq(condition_proc)
        end

        it 'adds field with dynamic readonly' do
          builder = described_class.new
          readonly_proc = proc { |ctx| ctx.record['status'] == 'closed' }
          builder.field :amount, type: :number, readonly: readonly_proc

          field = builder.fields[0]
          expect(field[:is_read_only]).to eq(readonly_proc)
        end

        it 'adds field with dynamic default value' do
          builder = described_class.new
          default_proc = proc { |ctx| ctx.caller.email }
          builder.field :email, type: :string, default: default_proc

          field = builder.fields[0]
          expect(field[:default_value]).to eq(default_proc)
        end

        it 'adds field with dynamic description' do
          builder = described_class.new
          description_proc = proc { |ctx| "Balance: #{ctx.record["balance"]}" }
          builder.field :amount, type: :number, description: description_proc

          field = builder.fields[0]
          expect(field[:description]).to eq(description_proc)
        end

        it 'adds field with dynamic options' do
          builder = described_class.new
          options_proc = proc { |ctx| ctx.record['categories'].map { |c| { label: c, value: c } } }
          builder.field :category, type: :string, widget: 'Dropdown', options: options_proc

          field = builder.fields[0]
          expect(field[:options]).to eq(options_proc)
        end

        it 'adds enum field with static enum_values' do
          builder = described_class.new
          values = %w[active inactive pending]
          builder.field :status, type: :enum, enum_values: values

          field = builder.fields[0]
          expect(field[:enum_values]).to eq(values)
        end

        it 'adds enum field with dynamic enum_values' do
          builder = described_class.new
          enum_proc = proc { |ctx| ctx.record['allowed_statuses'] }
          builder.field :status, type: :enum, enum_values: enum_proc

          field = builder.fields[0]
          expect(field[:enum_values]).to eq(enum_proc)
        end

        it 'adds field with static collection_name' do
          builder = described_class.new
          builder.field :customer_id, type: :string, collection_name: 'customers'

          field = builder.fields[0]
          expect(field[:collection_name]).to eq('customers')
        end

        it 'adds field with dynamic collection_name' do
          builder = described_class.new
          collection_proc = proc { |ctx| ctx.record['type'] == 'company' ? 'companies' : 'individuals' }
          builder.field :entity_id, type: :string, collection_name: collection_proc

          field = builder.fields[0]
          expect(field[:collection_name]).to eq(collection_proc)
        end
      end

      describe '#page' do
        it 'creates a page with nested fields' do
          builder = described_class.new
          builder.page do
            field :address, type: :string
            field :city, type: :string
            field :zip, type: :string
          end

          expect(builder.fields.length).to eq(1)
          page = builder.fields[0]
          expect(page[:type]).to eq('Layout')
          expect(page[:component]).to eq('Page')
          expect(page[:elements].length).to eq(3)
          expect(page[:elements][0][:label]).to eq('address')
        end
      end

      describe '#row' do
        it 'creates a row layout' do
          builder = described_class.new
          builder.row do
            field :first_name, type: :string
            field :last_name, type: :string
          end

          expect(builder.fields.length).to eq(1)
          row = builder.fields[0]
          expect(row[:type]).to eq('Layout')
          expect(row[:component]).to eq('Row')
          expect(row[:fields].length).to eq(2)
        end
      end

      describe '#separator' do
        it 'adds a separator' do
          builder = described_class.new
          builder.field :field1, type: :string
          builder.separator
          builder.field :field2, type: :string

          expect(builder.fields.length).to eq(3)
          separator = builder.fields[1]
          expect(separator[:type]).to eq('Layout')
          expect(separator[:component]).to eq('Separator')
        end
      end

      describe '#html' do
        it 'adds an HTML block' do
          builder = described_class.new
          html_content = '<p>This is <strong>important</strong></p>'
          builder.html(html_content)

          expect(builder.fields.length).to eq(1)
          html_block = builder.fields[0]
          expect(html_block[:type]).to eq('Layout')
          expect(html_block[:component]).to eq('HtmlBlock')
          expect(html_block[:content]).to eq(html_content)
        end
      end

      describe 'complex form' do
        it 'builds a complex form with multiple elements' do
          builder = described_class.new
          builder.instance_eval do
            field :email, type: :string, widget: 'TextInput'
            field :age, type: :number
            separator
            page do
              field :address, type: :string
              field :city, type: :string
              row { field :state, type: :string; field :zip, type: :string }
            end
            html '<p>Terms and conditions</p>'
            field :accept_terms, type: :boolean
          end

          expect(builder.fields.length).to eq(6)
          expect(builder.fields[0][:label]).to eq('email')
          expect(builder.fields[2][:component]).to eq('Separator')
          expect(builder.fields[3][:elements][2][:component]).to eq('Row')
          expect(builder.fields[5][:label]).to eq('accept_terms')
        end
      end
    end
  end
end

# rubocop:enable Style/Semicolon
