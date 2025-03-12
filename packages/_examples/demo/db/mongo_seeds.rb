Mongo::Departure.destroy_all
Mongo::Team.destroy_all
Mongo::User.destroy_all
Mongo::Tag.destroy_all
Mongo::Post.destroy_all
Mongo::Comment.destroy_all
Mongo::Author.destroy_all
Mongo::Band.destroy_all

# Create Teams and Departures
30.times do
  Mongo::Departure.create!(label: Faker::Travel::Airport.name(size: 'large', region: 'european_union'))
  Mongo::Team.create!(label: Faker::Sports::Football.team)
end

# Create Users
items = Mongo::Departure.all.to_a + Mongo::Team.all.to_a
30.times do
  addresses = []
  Faker::Number.number(digits: 1).times do
    addresses << Mongo::EmbeddedAddress.new(
      street: Faker::Address.street_address,
      city: Faker::Address.city,
      zip_code: Faker::Address.zip_code
    )
  end

  Mongo::User.create!(
    name: Faker::Name.name,
    item: items.sample,
    addresses: addresses
  )
end

# Create Posts
30.times do
  tags = []
  Faker::Number.number(digits: 1).times { tags << Mongo::Tag.create!(label: Faker::Adjective.positive) }

  Mongo::Post.create!(
    title: Faker::Quote.famous_last_words,
    body: Faker::Lorem.paragraphs,
    status: 'draft',
    int_field: rand(26),
    float_field: rand,
    array_field: [rand(26), rand(26)],
    big_decimal_field: BigDecimal(rand(10)),
    boolean_field: Faker::Boolean.boolean,
    boolean_field_2: Faker::Boolean.boolean,
    date_field: Date.new,
    date_time_field: DateTime.new,
    hash_field: { test: 1, 'foo' => 'xwcc' },
    range_field: Range.new(2, 5),
    regex_field: Regexp.new('foo'),
    set_field: Set[1, 2],
    sym_field: :test,
    string_sym_field: :foo,
    tags: tags
  )
end

# Create Comments and Authors
posts = Mongo::Post.all
50.times do
  Mongo::Comment.create!(
    name: Faker::String.random(length: 32),
    message: Faker::String.random(length: 254),
    post: posts.sample
  )

  Mongo::Author.create!(
    first_name: Faker::Name.first_name,
    last_name: Faker::Name.last_name,
    post: posts.sample
  )
end

10.times do
  Mongo::Band.create!(
    label: Mongo::Label.new(
      name: Faker::Music.band,
      section: Mongo::Section.new(
        content: Faker::Lorem.sentence,
        body: Faker::Lorem.paragraph
      )
    )
  )
end
