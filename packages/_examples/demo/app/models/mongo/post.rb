# frozen_string_literal: true

module Mongo
  class Post
    include Mongoid::Document
    include Mongoid::Timestamps

    field :title, type: String
    field :body, type: String
    field :status, type: Mongo::Enums::PostStatus
    field :int_field, type: Integer
    field :float_field, type: Float
    field :array_field, type: Array
    field :big_decimal_field, type: BigDecimal
    field :boolean_field, type: Mongoid::Boolean
    field :boolean_field_2, type: 'Boolean'
    field :date_field, type: Date
    field :date_time_field, type: DateTime
    field :hash_field, type: Hash
    field :range_field, type: Range
    field :regex_field, type: Regexp
    field :set_field, type: Set
    field :string_sym_field, type: Mongoid::StringifiedSymbol
    field :sym_field, type: Symbol

    has_many :comments, dependent: :destroy, class_name: 'Mongo::Comment'
    has_one :author, class_name: 'Mongo::Author'
    has_and_belongs_to_many :tags, class_name: 'Mongo::Tag'

    validates :title, presence: true
    validates :body, presence: { message: 'body is required' }
  end
end
