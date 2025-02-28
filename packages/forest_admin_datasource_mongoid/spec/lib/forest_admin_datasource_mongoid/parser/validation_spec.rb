require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Parser
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    describe Validation do
      before do
        logger = instance_double(Logger, log: nil)
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'auto' }) }
      let(:collection) { ForestAdminDatasourceMongoid::Collection.new(datasource, model, [{ prefix: nil, as_fields: [], as_models: [] }]) }

      context 'when the model has a before_validation callback' do
        let(:model) do
          model_class = Class.new do
            include Mongoid::Document
            before_validation :some_before_validation_callback
            validates :email, presence: true

            def some_before_validation_callback
              # Simulate callback
            end
          end
          Object.const_set(:PostDocument1, model_class)
          model_class
        end

        it 'returns empty validations' do
          result = collection.get_validations(model, 'email')
          expect(result).to eq([])
        end
      end

      context 'when the model does not have a before_validation callback' do
        let(:model) do
          model_class = Class.new do
            include Mongoid::Document
            field :email, type: String
            validates :email, presence: true
          end

          Object.const_set(:PostDocument2, model_class)
          model_class
        end

        it 'returns validations' do
          email_column = model.fields['email']
          result = collection.get_validations(model, email_column)

          expect(result).to eq([{ operator: Operators::PRESENT }])
        end
      end

      context 'when the model has a numericality validator' do
        context 'with a greater_than validation' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :age, type: Integer
              validates :age, numericality: { greater_than: 20 }
            end

            Object.const_set(:PostDocument3, model_class)
            model_class
          end

          it 'returns a greater_than validation' do
            age_column = model.fields['age']
            result = collection.get_validations(model, age_column)

            expect(result).to include({ operator: Operators::GREATER_THAN, value: 20 })
          end
        end

        context 'with a less_than validation' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :age, type: Integer
              validates :age, numericality: { less_than: 50 }
            end

            Object.const_set(:PostDocument4, model_class)
            model_class
          end

          it 'returns a less_than validation' do
            age_column = model.fields['age']
            result = collection.get_validations(model, age_column)

            expect(result).to include({ operator: Operators::LESS_THAN, value: 50 })
          end
        end
      end

      context 'when the model has a length validator' do
        context 'with a minimum length validation' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :title, type: String
              validates :title, length: { minimum: 5 }
            end

            Object.const_set(:PostDocument5, model_class)
            model_class
          end

          it 'returns a minimum length validation' do
            title_column = model.fields['title']
            result = collection.get_validations(model, title_column)

            expect(result).to include({ operator: Operators::LONGER_THAN, value: 5 })
          end
        end

        context 'with a maximum length validation' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :title, type: String
              validates :title, length: { maximum: 10 }
            end

            Object.const_set(:PostDocument6, model_class)
            model_class
          end

          it 'returns a maximum length validation' do
            title_column = model.fields['title']
            result = collection.get_validations(model, title_column)

            expect(result).to include({ operator: Operators::SHORTER_THAN, value: 10 })
          end
        end

        context 'with an exact length validator' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :title, type: String
              validates :title, length: { is: 8 }
            end

            Object.const_set(:PostDocument7, model_class)
            model_class
          end

          it 'returns an exact length validation' do
            title_column = model.fields['title']
            result = collection.get_validations(model, title_column)

            expect(result).to include({ operator: Operators::LONGER_THAN, value: 8 })
            expect(result).to include({ operator: Operators::SHORTER_THAN, value: 8 })
          end
        end
      end

      context 'when the model has a format validator' do
        context 'with a valid email format' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :email, type: String
              validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
            end

            Object.const_set(:PostDocument8, model_class)
            model_class
          end

          it 'returns a format validation for email' do
            email_column = model.fields['email']
            result = collection.get_validations(model, email_column)

            expect(result).to include({ operator: Operators::CONTAINS, value: "/^[a-zA-Z0-9.!\\\#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/" })
          end
        end

        context 'with a custom format validation' do
          let(:model) do
            model_class = Class.new do
              include Mongoid::Document
              field :username, type: String
              validates :username, format: { with: /\A[a-zA-Z0-9_]+\z/, message: 'only allows letters, numbers, and underscores' }
            end

            Object.const_set(:PostDocument9, model_class)
            model_class
          end

          it 'returns a custom format validation' do
            username_column = model.fields['username']
            result = collection.get_validations(model, username_column)

            expect(result).to include({ operator: Operators::CONTAINS, value: '/^[a-zA-Z0-9_]+$/' })
          end
        end
      end
    end
  end
end
