module Mongo
  class Comment
    include Mongoid::Document
    include Mongoid::Timestamps
    field :name, type: String
    field :message, type: String

    belongs_to :post, class_name: 'Mongo::Post'
  end
end
