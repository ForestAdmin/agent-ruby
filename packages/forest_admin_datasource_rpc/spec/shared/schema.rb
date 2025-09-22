RSpec.shared_context 'with introspection' do
  let(:introspection) do
    {
      charts: ['appointments'],
      collections: [
        {
          fields: {
            id: {
              column_type: 'Number',
              filter_operators: %w[greater_than not_in less_than not_equal equal missing in blank present],
              is_primary_key: true,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            name: {
              column_type: 'String',
              filter_operators: %w[contains ends_with greater_than not_in i_ends_with i_starts_with less_than not_contains
                                   starts_with not_equal equal like i_like missing in blank present i_contains],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            siren: {
              column_type: 'String',
              filter_operators: %w[contains ends_with greater_than not_in i_ends_with i_starts_with less_than not_contains
                                   starts_with not_equal equal like i_like missing in blank present i_contains],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            created_at: {
              column_type: 'Date',
              filter_operators: %w[before greater_than not_in less_than after not_equal today equal missing
                                   after_x_hours_ago before_x_hours_ago future past yesterday previous_week
                                   previous_month previous_quarter previous_year previous_week_to_date
                                   previous_month_to_date previous_quarter_to_date previous_year_to_date
                                   previous_x_days previous_x_days_to_date in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            updated_at: {
              column_type: 'Date',
              filter_operators: %w[before greater_than not_in less_than after not_equal today equal missing
                                   after_x_hours_ago before_x_hours_ago future past yesterday previous_week
                                   previous_month previous_quarter previous_year previous_week_to_date
                                   previous_month_to_date previous_quarter_to_date previous_year_to_date
                                   previous_x_days previous_x_days_to_date in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            products: {
              foreign_collection: 'Product',
              type: 'OneToMany',
              origin_key: 'manufacturer_id',
              origin_key_target: 'id'
            }
          },
          countable: true,
          searchable: true,
          charts: [],
          segments: [],
          actions: {},
          name: 'Manufacturer'
        },
        {
          fields: {
            id: {
              column_type: 'Number',
              filter_operators: %w[greater_than not_in less_than not_equal equal missing in blank present],
              is_primary_key: true,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            label: {
              column_type: 'String',
              filter_operators: %w[contains ends_with greater_than not_in i_ends_with i_starts_with less_than not_contains
                                   starts_with not_equal equal like i_like missing in blank present i_contains],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            quantity: {
              column_type: 'Number',
              filter_operators: %w[greater_than not_in less_than not_equal equal missing in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            manufacturer_id: {
              column_type: 'Number',
              filter_operators: %w[greater_than not_in less_than not_equal equal missing in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            next_restocking_date: {
              column_type: 'Dateonly',
              filter_operators: %w[before greater_than not_in less_than after not_equal today equal missing
                                   after_x_hours_ago before_x_hours_ago future past yesterday previous_week
                                   previous_month previous_quarter previous_year previous_week_to_date
                                   previous_month_to_date previous_quarter_to_date previous_year_to_date
                                   previous_x_days previous_x_days_to_date in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            created_at: {
              column_type: 'Date',
              filter_operators: %w[before greater_than not_in less_than after not_equal today equal missing
                                   after_x_hours_ago before_x_hours_ago future past yesterday previous_week
                                   previous_month previous_quarter previous_year previous_week_to_date
                                   previous_month_to_date previous_quarter_to_date previous_year_to_date
                                   previous_x_days previous_x_days_to_date in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            updated_at: {
              column_type: 'Date',
              filter_operators: %w[before greater_than not_in less_than after not_equal today equal missing
                                   after_x_hours_ago before_x_hours_ago future past yesterday previous_week
                                   previous_month previous_quarter previous_year previous_week_to_date
                                   previous_month_to_date previous_quarter_to_date previous_year_to_date
                                   previous_x_days previous_x_days_to_date in blank present],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validations: [],
              type: 'Column'
            },
            manufacturer: {
              foreign_collection: 'Manufacturer',
              type: 'ManyToOne',
              foreign_key: 'manufacturer_id',
              foreign_key_target: 'id'
            }
          },
          countable: true,
          searchable: true,
          charts: ['groupByManufacturer'],
          segments: ['test'],
          actions: {
            'add product': {
              scope: 'single',
              form: [
                {
                  type: 'Number',
                  label: 'amount',
                  id: 'amount',
                  description: 'The amount (USD) to charge the credit card. Example: 42.50',
                  is_required: true,
                  is_read_only: false,
                  if_condition: nil,
                  value: nil,
                  default_value: nil,
                  collection_name: nil,
                  enum_values: nil,
                  placeholder: nil
                },
                {
                  type: 'String',
                  label: 'label',
                  id: 'label',
                  description: nil,
                  is_required: false,
                  is_read_only: false,
                  if_condition: nil,
                  value: nil,
                  default_value: nil,
                  collection_name: nil,
                  enum_values: nil,
                  placeholder: nil
                },
                {
                  type: 'File',
                  label: 'product picture',
                  id: 'product picture',
                  description: nil,
                  is_required: false,
                  is_read_only: false,
                  if_condition: {},
                  value: nil,
                  default_value: {},
                  collection_name: nil,
                  enum_values: nil,
                  placeholder: nil,
                  widget: 'FilePicker',
                  extensions: %w[png jpg],
                  max_size_mb: 20,
                  max_count: nil
                }
              ],
              is_generate_file: false,
              description: nil,
              submit_button_label: nil,
              execute: {},
              static_form: false
            }
          },
          name: 'Product'
        }
      ]
    }
  end
end
