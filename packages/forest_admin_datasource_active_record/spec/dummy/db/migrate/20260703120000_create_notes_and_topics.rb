class CreateNotesAndTopics < ActiveRecord::Migration[7.1]
  def change
    create_table :topics

    create_table :notes do |t|
      t.string :notable_type
      t.integer :notable_id
    end

    add_column :accounts, :note_id, :integer, null: true
  end
end
