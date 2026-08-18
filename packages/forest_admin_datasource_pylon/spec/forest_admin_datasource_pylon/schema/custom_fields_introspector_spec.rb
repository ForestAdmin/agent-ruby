RSpec.describe ForestAdminDatasourcePylon::Schema::CustomFieldsIntrospector do
  let(:client) { instance_double(ForestAdminDatasourcePylon::Client) }
  let(:introspector) { described_class.new(client) }
  let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

  def definition(type, slug: 'severity', **extra)
    { 'id' => 'cf_1', 'slug' => slug, 'label' => slug.capitalize, 'type' => type,
      'object_type' => 'issue', 'is_read_only' => false }.merge(extra)
  end

  def select_metadata(*slugs)
    { 'select_metadata' => { 'options' => slugs.map { |slug| { 'label' => slug.upcase, 'slug' => slug } } } }
  end

  # `object_type` is what Pylon indexes its definitions by, and each accessor
  # reads the type of the collection it feeds.
  describe 'the object type of each accessor' do
    it 'reads the definitions of the matching Pylon object type' do
      %w[issue account contact].each do |object_type|
        allow(client).to receive(:fetch_custom_fields).with(object_type).and_return([])
      end

      introspector.issue_custom_fields
      introspector.account_custom_fields
      introspector.contact_custom_fields

      expect(client).to have_received(:fetch_custom_fields).with('issue')
      expect(client).to have_received(:fetch_custom_fields).with('account')
      expect(client).to have_received(:fetch_custom_fields).with('contact')
    end
  end

  describe 'column types' do
    it 'maps every Pylon type onto the Forest column type holding it' do
      definitions = %w[text url user number decimal boolean date datetime multiselect]
                    .map { |type| definition(type, slug: type) }
      allow(client).to receive(:fetch_custom_fields).with('issue').and_return(definitions)

      types = introspector.issue_custom_fields.to_h { |cf| [cf[:column_name], cf[:schema].column_type] }

      expect(types).to eq('text' => 'String', 'url' => 'String', 'user' => 'String',
                          'number' => 'Number', 'decimal' => 'Number', 'boolean' => 'Boolean',
                          'date' => 'Dateonly', 'datetime' => 'Date', 'multiselect' => 'Json')
    end

    # A type this datasource cannot map would filter and display wrong, which is
    # worse for the operator than a column that is not there.
    it 'skips a type it cannot map, and says which field it left out' do
      allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
      allow(client).to receive(:fetch_custom_fields).with('account')
                                                    .and_return([definition('holographic', slug: 'tier')])

      expect(introspector.account_custom_fields).to eq([])
      expect(ForestAdminDatasourcePylon.logger)
        .to have_received(:warn).with(/'tier' on account has type "holographic".*skipping/)
    end

    it 'skips a definition carrying no slug, which nothing could be read by' do
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('text', slug: ''), 'not a hash'])

      expect(introspector.issue_custom_fields).to eq([])
    end
  end

  describe 'a select field' do
    it 'advertises the option slugs, which are the values Pylon reads and filters' do
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('select', **select_metadata('p1', 'p2'))])

      schema = introspector.issue_custom_fields.first[:schema]

      expect(schema.column_type).to eq('Enum')
      expect(schema.enum_values).to eq(%w[p1 p2])
    end

    it 'reads a multiselect the same way' do
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('multiselect', **select_metadata('eu'))])

      expect(introspector.issue_custom_fields.first[:schema].column_type).to eq('Json')
    end

    # Forest refuses an Enum carrying no value, so a select whose options were
    # all removed still shows what it holds instead of disappearing.
    it 'falls back to String when every option is gone' do
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('select', **select_metadata)])

      schema = introspector.issue_custom_fields.first[:schema]

      expect(schema.column_type).to eq('String')
      expect(schema.enum_values).to eq([])
      expect(schema.filter_operators).to include(operators::I_CONTAINS)
    end

    it 'ignores an option with no slug rather than advertising a blank value' do
      metadata = { 'select_metadata' => { 'options' => [{ 'label' => 'P1' }, { 'slug' => 'p2' }, 'nope'] } }
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('select', **metadata)])

      expect(introspector.issue_custom_fields.first[:schema].enum_values).to eq(%w[p2])
    end
  end

  describe 'filter operators' do
    def operators_of(type, **extra)
      allow(client).to receive(:fetch_custom_fields).with('issue').and_return([definition(type, **extra)])

      introspector.issue_custom_fields.first[:schema].filter_operators
    end

    it 'lets a text field be matched, listed, checked for presence and searched' do
      expect(operators_of('text')).to eq([operators::EQUAL, operators::IN, operators::NOT_IN,
                                          operators::PRESENT, operators::BLANK, operators::MISSING,
                                          operators::CONTAINS, operators::I_CONTAINS,
                                          operators::NOT_CONTAINS, operators::NOT_I_CONTAINS])
    end

    it 'gives a date field the bounds Pylon compares dates with' do
      expect(operators_of('datetime')).to include(operators::GREATER_THAN, operators::LESS_THAN)
    end

    # Pylon spells the bare comparisons `time_is_after` / `time_is_before` and
    # documents nothing else, so a numeric range would travel as a time filter.
    #
    # The presence family carries MISSING next to PRESENT and BLANK: Pylon spells
    # absence through `is_unset` alone, and a field left without MISSING would
    # refuse the very filter its endpoint can answer.
    it 'gives a number no comparison, only equality and presence' do
      expect(operators_of('number'))
        .to eq([operators::EQUAL, operators::IN, operators::NOT_IN,
                operators::PRESENT, operators::BLANK, operators::MISSING])
    end

    it 'gives a boolean equality and presence' do
      expect(operators_of('boolean')).to eq([operators::EQUAL, operators::IN, operators::NOT_IN,
                                             operators::PRESENT, operators::BLANK, operators::MISSING])
    end

    # A membership filter is not part of what a custom field accepts, and no
    # in-memory pass can stand in for one on a list.
    it 'leaves a multiselect unfilterable' do
      expect(operators_of('multiselect')).to eq([])
    end

    it 'keeps an enum to equality and presence' do
      expect(operators_of('select', **select_metadata('p1')))
        .to eq([operators::EQUAL, operators::IN, operators::NOT_IN,
                operators::PRESENT, operators::BLANK, operators::MISSING])
    end
  end

  # Writes land in story 7 (EXT-11), which is also where Pylon's own
  # `is_read_only` starts being honoured; no endpoint sorts, ever.
  describe 'the schema every custom field gets' do
    it 'is read-only and unsortable, whatever Pylon declares' do
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('text', 'is_read_only' => false)])

      schema = introspector.issue_custom_fields.first[:schema]

      expect(schema.is_read_only).to be(true)
      expect(schema.is_sortable).to be(false)
    end

    # The slug is both the key a read payload indexes the value by and the
    # `field` a filter sends, so the column carries it unchanged.
    it 'names the column after the Pylon slug, with nothing else to keep in step' do
      allow(client).to receive(:fetch_custom_fields).with('issue')
                                                    .and_return([definition('text', slug: 'sev_level')])

      expect(introspector.issue_custom_fields.first.keys).to eq(%i[column_name schema])
      expect(introspector.issue_custom_fields.first[:column_name]).to eq('sev_level')
    end
  end
end
