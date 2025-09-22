module Mongo
  class Label
    include Mongoid::Document

    field :name, type: String

    embedded_in :band, class_name: 'Mongo::Band'
    embeds_one :section, class_name: 'Mongo::Section'
  end
end
