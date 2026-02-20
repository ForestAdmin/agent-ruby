class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.string :title
      t.string :doc_type
      t.references :documentable, polymorphic: true, null: false

      t.timestamps
    end
  end
end
