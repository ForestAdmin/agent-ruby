class CreateParentsChildrenAndLeaves < ActiveRecord::Migration[7.1]
  def change
    create_table :parents

    create_table :children do |t|
      t.references :owner, polymorphic: true
    end

    create_table :leaves do |t|
      t.integer :custom_child_id
    end
  end
end
