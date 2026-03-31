# rubocop:disable RSpec/VerifiedDoubles
require 'spec_helper'
require 'base64'
require 'cgi'
require 'forest_admin_datasource_customizer'
require 'forest_admin_agent'

# Stub ActiveStorage if not available
module ActiveStorage; end unless defined?(ActiveStorage)

require_relative '../../../../lib/forest_admin_rails/plugins/active_storage'

RSpec.describe ForestAdminRails::Plugins::ActiveStorage do
  subject(:plugin) { described_class.new }

  let(:datasource_customizer) do
    instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer, collections: collections)
  end
  let(:collections) { { 'Order' => order_collection, 'User' => user_collection } }
  let(:order_collection) { build_collection(order_model_class) }
  let(:user_collection) { build_collection(user_model_class) }

  let(:order_model_class) do
    klass = Class.new do
      def self.reflect_on_all_attachments; end
      def self.where(_conditions); end
      def self.find(_id); end
    end
    allow(klass).to receive(:reflect_on_all_attachments).and_return([document_attachment])
    klass
  end

  let(:user_model_class) do
    klass = Class.new do
      def self.reflect_on_all_attachments; end
    end
    allow(klass).to receive(:reflect_on_all_attachments).and_return([])
    klass
  end

  let(:document_attachment) do
    double(:attachment, name: :document, macro: :has_one_attached)
  end

  def build_collection(model_class)
    decorator = Struct.new(:model).new(model_class)
    collection = Struct.new(:schema, :added_fields, :write_handlers, :removed_fields) do
      def add_field(name, definition)
        added_fields[name] = definition
      end

      def replace_field_writing(name, &block)
        write_handlers[name] = block
      end

      def remove_field(name)
        removed_fields << name
      end
    end.new({ fields: {} }, {}, {}, [])

    collection.define_singleton_method(:collection) { decorator }
    collection
  end

  describe '#run' do
    it 'adds file field for has_one_attached' do
      plugin.run(datasource_customizer, nil, {})

      expect(order_collection.added_fields).to have_key('document')
      expect(order_collection.write_handlers).to have_key('document')
    end

    it 'skips collections without attachments' do
      plugin.run(datasource_customizer, nil, {})

      expect(user_collection.added_fields).to be_empty
    end

    context 'with :only option' do
      it 'only processes whitelisted collections' do
        plugin.run(datasource_customizer, nil, { only: ['User'] })

        expect(order_collection.added_fields).to be_empty
      end
    end

    context 'with :except option' do
      it 'skips blacklisted collections' do
        plugin.run(datasource_customizer, nil, { except: ['Order'] })

        expect(order_collection.added_fields).to be_empty
      end
    end

    it 'skips if field already exists' do
      order_collection.schema = { fields: { 'document' => true } }

      plugin.run(datasource_customizer, nil, {})

      expect(order_collection.added_fields).to be_empty
    end
  end

  describe '#compute_values (via add_field)' do
    let(:blob) do
      double(:blob,
             content_type: 'application/pdf',
             filename: double(:filename, to_s: 'report.pdf'),
             download: 'file-content')
    end

    let(:attachment_proxy) do
      double(:attachment_proxy, attached?: true, blob: blob)
    end

    let(:model_instance) do
      double(:order, id: 1).tap do |inst|
        allow(inst).to receive(:public_send).with('document').and_return(attachment_proxy)
      end
    end

    let(:query_result) do
      double(:relation).tap do |qr|
        allow(qr).to receive_messages(includes: qr, index_by: { 1 => model_instance })
      end
    end

    before do
      allow(order_model_class).to receive(:where).and_return(query_result)
      plugin.run(datasource_customizer, nil, {})
    end

    it 'returns full data URI for single record (detail view)' do
      computed_def = order_collection.added_fields['document']
      records = [{ 'id' => 1 }]
      result = computed_def.get_values(records, nil)

      expected = "data:application/pdf;name=#{CGI.escape("report.pdf")};base64,#{Base64.strict_encode64("file-content")}"
      expect(result).to eq([expected])
    end

    it 'returns metadata-only data URI for multiple records (list view)' do
      computed_def = order_collection.added_fields['document']
      records = [{ 'id' => 1 }, { 'id' => 2 }]
      result = computed_def.get_values(records, nil)

      expect(result.first).to eq("data:application/pdf;name=#{CGI.escape("report.pdf")};base64,")
    end

    it 'returns nil for records without attachments' do
      no_attachment = double(:relation)
      allow(no_attachment).to receive_messages(includes: no_attachment, index_by: {})
      allow(order_model_class).to receive(:where).and_return(no_attachment)

      computed_def = order_collection.added_fields['document']
      records = [{ 'id' => 99 }]
      result = computed_def.get_values(records, nil)

      expect(result).to eq([nil])
    end
  end

  describe '#handle_write (via replace_field_writing)' do
    let(:attachment_proxy) { double(:attachment_proxy) }
    let(:model_instance) do
      double(:order).tap do |inst|
        allow(inst).to receive(:public_send).with('document').and_return(attachment_proxy)
      end
    end

    let(:condition_tree) { double(:condition_tree, value: 42) }
    let(:filter) { double(:filter, condition_tree: condition_tree) }
    let(:context) { double(:context, filter: filter) }

    before do
      allow(order_model_class).to receive(:find).with(42).and_return(model_instance)
      plugin.run(datasource_customizer, nil, {})
    end

    it 'purges attachment when value is nil' do
      allow(attachment_proxy).to receive(:attached?).and_return(true)
      allow(attachment_proxy).to receive(:purge)

      write_handler = order_collection.write_handlers['document']
      result = write_handler.call(nil, context)

      expect(result).to eq({})
      expect(attachment_proxy).to have_received(:purge)
    end

    it 'attaches file from data URI' do
      data_uri = "data:image/png;base64,#{Base64.strict_encode64("png-data")}"
      allow(attachment_proxy).to receive(:attach)

      write_handler = order_collection.write_handlers['document']
      result = write_handler.call(data_uri, context)

      expect(result).to eq({})
      expect(attachment_proxy).to have_received(:attach).with(
        io: an_instance_of(StringIO),
        filename: 'document.png',
        content_type: 'image/png'
      )
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
