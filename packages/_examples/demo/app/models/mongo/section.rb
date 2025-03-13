module Mongo
  class Section
    include Mongoid::Document
    field :content, type: String
    field :body, type: String

    embedded_in :label, class_name: 'Mongo::Label'
  end
end
