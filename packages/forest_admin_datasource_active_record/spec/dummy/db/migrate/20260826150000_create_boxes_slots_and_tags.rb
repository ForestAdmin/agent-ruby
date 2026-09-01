class CreateBoxesSlotsAndTags < ActiveRecord::Migration[7.1]
  def change
    create_table :boxes

    create_table :slots do |t|
      t.references :box
    end

    create_table :tags do |t|
      t.integer :custom_slot_id
    end
  end
end
