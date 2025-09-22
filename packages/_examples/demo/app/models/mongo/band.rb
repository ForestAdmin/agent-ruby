module Mongo
  class Band
    include Mongoid::Document
    include Mongoid::Timestamps

    embeds_one :label, class_name: 'Mongo::Label'
  end
end
