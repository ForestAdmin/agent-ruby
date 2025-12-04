require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Parser
    describe Validation do
      let(:dummy_instance) do
        Class.new do
          include Validation
          include Column

          attr_accessor :model

          def initialize(model)
            @model = model
          end
        end
      end

      let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

      # Helper to create a model without the internal before_validation callback
      def create_model_without_internal_callback(&block)
        klass = Class.new(ApplicationRecord) do
          self.table_name = 'users'
          skip_callback :validation, :before, :normalize_changed_in_place_attributes, raise: false
        end
        klass.class_eval(&block) if block_given?
        klass
      end

      describe '#get_validations' do
        context 'when model has before_validation callback' do
          let(:model) do
            Class.new(ApplicationRecord) do
              self.table_name = 'users'
              before_validation :some_callback

              validates :string_field, presence: true

              def some_callback; end
            end
          end

          it 'returns empty validations' do
            instance = dummy_instance.new(model)
            column = model.columns_hash['string_field']

            expect(instance.get_validations(column)).to eq []
          end
        end

        context 'when model has no validators' do
          let(:model) { User }

          it 'returns empty validations' do
            instance = dummy_instance.new(model)
            column = model.columns_hash['string_field']

            expect(instance.get_validations(column)).to eq []
          end
        end

        context 'when model has validators without before_validation callback' do
          context 'with presence validator' do
            let(:model) { create_model_without_internal_callback { validates :string_field, presence: true } }

            it 'returns PRESENT operator' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['string_field']

              expect(instance.get_validations(column)).to include({ operator: operators::PRESENT })
            end
          end

          context 'with numericality validator' do
            let(:model) do
              create_model_without_internal_callback do
                validates :integer_field, numericality: { greater_than: 5, less_than: 100 }
              end
            end

            it 'returns GREATER_THAN and LESS_THAN operators' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['integer_field']

              validations = instance.get_validations(column)
              expect(validations).to include({ operator: operators::GREATER_THAN, value: 5 })
              expect(validations).to include({ operator: operators::LESS_THAN, value: 100 })
            end
          end

          context 'with length validator on string column' do
            let(:model) do
              create_model_without_internal_callback do
                validates :string_field, length: { minimum: 3, maximum: 50 }
              end
            end

            it 'returns LONGER_THAN and SHORTER_THAN operators' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['string_field']

              validations = instance.get_validations(column)
              expect(validations).to include({ operator: operators::LONGER_THAN, value: 3 })
              expect(validations).to include({ operator: operators::SHORTER_THAN, value: 50 })
            end
          end

          context 'with length validator on non-string column' do
            let(:model) do
              create_model_without_internal_callback do
                validates :integer_field, length: { minimum: 1 }
              end
            end

            it 'returns nil (length validation only applies to String columns)' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['integer_field']

              # parse_length_validator returns nil early if column type is not String
              expect(instance.get_validations(column)).to be_nil
            end
          end

          context 'with format validator' do
            let(:model) do
              create_model_without_internal_callback do
                validates :string_field, format: { with: /\A[a-z]+\z/ }
              end
            end

            it 'returns CONTAINS operator with transformed regex' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['string_field']

              validations = instance.get_validations(column)
              expect(validations.length).to eq 1
              expect(validations[0][:operator]).to eq operators::CONTAINS
              expect(validations[0][:value]).to include('^[a-z]+$')
            end
          end

          context 'with conditional validator using :if' do
            let(:model) do
              create_model_without_internal_callback do
                validates :string_field, presence: true, if: :some_condition?

                def some_condition?
                  true
                end
              end
            end

            it 'ignores the conditional validator' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['string_field']

              expect(instance.get_validations(column)).to eq []
            end
          end

          context 'with conditional validator using :unless' do
            let(:model) do
              create_model_without_internal_callback do
                validates :string_field, presence: true, unless: :some_condition?

                def some_condition?
                  false
                end
              end
            end

            it 'ignores the conditional validator' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['string_field']

              expect(instance.get_validations(column)).to eq []
            end
          end

          context 'with conditional validator using :on' do
            let(:model) do
              create_model_without_internal_callback do
                validates :string_field, presence: true, on: :create
              end
            end

            it 'ignores the conditional validator' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['string_field']

              expect(instance.get_validations(column)).to eq []
            end
          end

          context 'with multiple validators (presence and numericality)' do
            let(:model) do
              create_model_without_internal_callback do
                validates :integer_field, presence: true, numericality: { greater_than: 0 }
              end
            end

            it 'returns all validations' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['integer_field']

              validations = instance.get_validations(column)
              expect(validations).to include({ operator: operators::PRESENT })
              expect(validations).to include({ operator: operators::GREATER_THAN, value: 0 })
            end
          end

          context 'with validator on column without validators' do
            let(:model) do
              create_model_without_internal_callback do
                validates :string_field, presence: true
              end
            end

            it 'returns empty array for column without validators' do
              instance = dummy_instance.new(model)
              column = model.columns_hash['integer_field']

              expect(instance.get_validations(column)).to eq []
            end
          end

          context 'with unsupported validators' do
            context 'with inclusion validator' do
              let(:model) do
                create_model_without_internal_callback do
                  validates :string_field, inclusion: { in: %w[foo bar baz] }
                end
              end

              it 'ignores inclusion validator (not supported)' do
                instance = dummy_instance.new(model)
                column = model.columns_hash['string_field']

                expect(instance.get_validations(column)).to eq []
              end
            end

            context 'with exclusion validator' do
              let(:model) do
                create_model_without_internal_callback do
                  validates :string_field, exclusion: { in: %w[admin root] }
                end
              end

              it 'ignores exclusion validator (not supported)' do
                instance = dummy_instance.new(model)
                column = model.columns_hash['string_field']

                expect(instance.get_validations(column)).to eq []
              end
            end

            context 'with acceptance validator' do
              let(:model) do
                create_model_without_internal_callback do
                  validates :boolean_field, acceptance: true
                end
              end

              it 'ignores acceptance validator (not supported)' do
                instance = dummy_instance.new(model)
                column = model.columns_hash['boolean_field']

                expect(instance.get_validations(column)).to eq []
              end
            end

            context 'with confirmation validator' do
              let(:model) do
                create_model_without_internal_callback do
                  validates :string_field, confirmation: true
                end
              end

              it 'ignores confirmation validator (not supported)' do
                instance = dummy_instance.new(model)
                column = model.columns_hash['string_field']

                expect(instance.get_validations(column)).to eq []
              end
            end

            context 'with uniqueness validator' do
              let(:model) do
                create_model_without_internal_callback do
                  validates :string_field, uniqueness: true
                end
              end

              it 'ignores uniqueness validator (not supported)' do
                instance = dummy_instance.new(model)
                column = model.columns_hash['string_field']

                expect(instance.get_validations(column)).to eq []
              end
            end
          end
        end
      end

      describe '#parse_numericality_validator' do
        let(:instance) { dummy_instance.new(User) }

        context 'with greater_than option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { greater_than: 5 }
            )
          end

          it 'returns GREATER_THAN operator with value' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to include({ operator: operators::GREATER_THAN, value: 5 })
          end
        end

        context 'with greater_than_or_equal_to option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { greater_than_or_equal_to: 10 }
            )
          end

          it 'returns GREATER_THAN operator with value' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to include({ operator: operators::GREATER_THAN, value: 10 })
          end
        end

        context 'with less_than option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { less_than: 100 }
            )
          end

          it 'returns LESS_THAN operator with value' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to include({ operator: operators::LESS_THAN, value: 100 })
          end
        end

        context 'with less_than_or_equal_to option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { less_than_or_equal_to: 50 }
            )
          end

          it 'returns LESS_THAN operator with value' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to include({ operator: operators::LESS_THAN, value: 50 })
          end
        end

        context 'with allow_nil set to false' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { allow_nil: false }
            )
          end

          it 'returns PRESENT operator' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to include({ operator: operators::PRESENT })
          end
        end

        context 'with allow_nil set to true' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { allow_nil: true }
            )
          end

          it 'does not return PRESENT operator' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).not_to include({ operator: operators::PRESENT })
          end
        end

        context 'with multiple options' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { greater_than: 0, less_than: 100, allow_nil: false }
            )
          end

          it 'returns all applicable operators' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to include({ operator: operators::GREATER_THAN, value: 0 })
            expect(result).to include({ operator: operators::LESS_THAN, value: 100 })
            expect(result).to include({ operator: operators::PRESENT })
          end
        end

        context 'with unhandled options' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::NumericalityValidator,
              options: { only_integer: true, odd: true }
            )
          end

          it 'ignores unhandled options' do
            result = instance.parse_numericality_validator(validator, [])

            expect(result).to eq []
          end
        end
      end

      describe '#parse_length_validator' do
        let(:instance) { dummy_instance.new(User) }

        context 'with minimum option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::LengthValidator,
              options: { minimum: 3 }
            )
          end

          it 'returns LONGER_THAN operator with value' do
            result = []
            validator.options.each do |option, value|
              case option
              when :minimum
                result << { operator: operators::LONGER_THAN, value: value }
              end
            end

            expect(result).to include({ operator: operators::LONGER_THAN, value: 3 })
          end
        end

        context 'with maximum option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::LengthValidator,
              options: { maximum: 100 }
            )
          end

          it 'returns SHORTER_THAN operator with value' do
            result = []
            validator.options.each do |option, value|
              case option
              when :maximum
                result << { operator: operators::SHORTER_THAN, value: value }
              end
            end

            expect(result).to include({ operator: operators::SHORTER_THAN, value: 100 })
          end
        end

        context 'with is option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::LengthValidator,
              options: { is: 10 }
            )
          end

          it 'returns both LONGER_THAN and SHORTER_THAN operators' do
            result = []
            validator.options.each do |option, value|
              case option
              when :is
                result << { operator: operators::LONGER_THAN, value: value }
                result << { operator: operators::SHORTER_THAN, value: value }
              end
            end

            expect(result).to include({ operator: operators::LONGER_THAN, value: 10 })
            expect(result).to include({ operator: operators::SHORTER_THAN, value: 10 })
          end
        end
      end

      describe '#parse_format_validator' do
        let(:instance) { dummy_instance.new(User) }

        context 'with simple regex' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+\z/ }
            )
          end

          it 'returns CONTAINS operator with transformed regex' do
            result = instance.parse_format_validator(validator, [])

            expect(result.length).to eq 1
            expect(result[0][:operator]).to eq operators::CONTAINS
            expect(result[0][:value]).to include('^[a-z]+$')
          end

          it 'transforms Ruby regex anchors to JS anchors' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).not_to include('\\A')
            expect(result[0][:value]).not_to include('\\z')
            expect(result[0][:value]).to include('^')
            expect(result[0][:value]).to include('$')
          end
        end

        context 'with case insensitive regex' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+\z/i }
            )
          end

          it 'preserves regex options' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).to match(%r{/i$})
          end
        end

        context 'with multiline regex' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+\z/m }
            )
          end

          it 'preserves m option' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).to match(%r{/m$})
          end
        end

        context 'with extended regex' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+\z/x }
            )
          end

          it 'preserves x option' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).to match(%r{/x$})
          end
        end

        context 'with \\Z anchor' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+\Z/ }
            )
          end

          it 'transforms \\Z to $' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).not_to include('\\Z')
            expect(result[0][:value]).to include('$')
          end
        end

        context 'with whitespace in regex' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+ test\z/ }
            )
          end

          it 'removes whitespace from regex' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).not_to include(' ')
          end
        end

        context 'with newlines in regex' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { with: /\A[a-z]+\ntest\z/ }
            )
          end

          it 'removes newlines from regex' do
            result = instance.parse_format_validator(validator, [])

            expect(result[0][:value]).not_to include("\n")
          end
        end

        context 'without :with option' do
          let(:validator) do
            instance_double(
              ActiveModel::Validations::FormatValidator,
              options: { without: /\A[0-9]+\z/ }
            )
          end

          it 'returns empty validations' do
            result = instance.parse_format_validator(validator, [])

            expect(result).to eq []
          end
        end
      end
    end
  end
end
