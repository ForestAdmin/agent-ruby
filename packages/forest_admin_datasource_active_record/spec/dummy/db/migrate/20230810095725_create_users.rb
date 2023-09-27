class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.references :car, null: false, foreign_key: true

      t.string :first_name
      t.string :last_name

      t.string :string_field
      t.text :text_field
      t.boolean :boolean_field
      t.date :date_field
      t.datetime :datetime_field
      t.integer :integer_field
      t.float :float_field
      t.decimal :decimal_field
      t.json :json_field
      t.time :time_field
      t.binary :binary_field
      t.integer :enum_field, default: 0
      # t.jsonb :options_b
      # t.hstore :options_hstore
      # t.citext :citext_field
      # t.uuid :uuid

      t.timestamps
    end
  end
end
