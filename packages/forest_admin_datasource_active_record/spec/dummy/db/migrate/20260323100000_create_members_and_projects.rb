class CreateMembersAndProjects < ActiveRecord::Migration[7.0]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :members do |t|
      t.references :memberable, polymorphic: true, null: false
      t.references :user, null: false
      t.timestamps
    end
  end
end
