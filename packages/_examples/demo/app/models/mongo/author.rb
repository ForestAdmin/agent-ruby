module Mongo
  class Author
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mongoid::Attributes::Dynamic

    field :first_name, type: String
    field :last_name, type: String

    belongs_to :post, class_name: 'Mongo::Post'
  end
end
