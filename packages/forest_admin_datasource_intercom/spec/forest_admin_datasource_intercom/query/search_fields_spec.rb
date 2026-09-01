module ForestAdminDatasourceIntercom
  RSpec.describe Query::SearchFields do
    def table(fields: {}, refused: {}, path: 'tickets/search', measured_at: nil, candidates: [])
      described_class.build(
        'endpoints' => { 'tickets' => { 'path' => path, 'measured_at' => measured_at, 'fields' => fields,
                                        'refused' => refused, 'candidates' => candidates } }
      )['tickets']
    end

    def field_row(overrides = {})
      { 'field' => 'created_at', 'type' => 'date', 'operators' => ['>', '<'], 'source' => 'spec' }.merge(overrides)
    end

    describe 'the committed table' do
      # The schema derives its filters from this file, so a malformed row is a
      # boot failure rather than a column nobody can explain. Reading it here is
      # what turns that guarantee into a test.
      it 'reads the two search endpoints' do
        expect(described_class.endpoints).to eq(%w[conversations tickets])
      end

      it 'names the path each endpoint is searched through' do
        expect(described_class.fetch('conversations').path).to eq('conversations/search')
        expect(described_class.fetch('tickets').path).to eq('tickets/search')
      end

      # The one thing lot 1 measured about the field lists: `/tickets/search`
      # refuses `company_id`, which the specification lists on a ticket.
      it 'refuses company_id on tickets, with the measurement as its reason' do
        refusal = described_class.fetch('tickets').refusal('company_id')

        expect(refusal.reason).to include('invalid_field')
        expect(refusal).to be_measured
      end

      # The columns the agent derives from the parts of a ticket: Intercom
      # filters none of them, and lot 1 published them without an operator.
      it 'refuses every column derived from the parts of a ticket' do
        refused = described_class.fetch('tickets').refused.keys

        expect(refused).to include('closed_at', 'closed_by_name', 'last_reply_at', 'last_responder_name',
                                   'last_responder_type')
      end

      it 'keeps the ticket attributes unfilterable while the arbitration stands' do
        expect(described_class.fetch('tickets').ticket_attributes['filterable']).to be(false)
      end

      # Until the probe runs against the customer's workspace, the date rows are
      # the only ones a measurement backs.
      it 'reports which rows nothing has measured yet' do
        conversations = described_class.fetch('conversations')

        expect(conversations).not_to be_measured
        expect(conversations.unmeasured_fields.map(&:column)).not_to include('created_at', 'updated_at')
      end

      it 'declares no column both filterable and refused' do
        described_class.endpoints.each do |name|
          endpoint = described_class.fetch(name)

          expect(endpoint.filterable_columns & endpoint.refused.keys).to be_empty
        end
      end

      # A candidate is what the probe enumerates on top of the table; one that
      # is already declared would be probed twice and read as a discovery.
      it 'names no candidate already declared as a field' do
        described_class.endpoints.each do |name|
          endpoint = described_class.fetch(name)

          expect(endpoint.candidates & endpoint.fields.values.map(&:field)).to be_empty
        end
      end
    end

    # The README is where an operator reads what they may filter on before the
    # interface shows it to them, so it is checked against the table rather than
    # left to drift from it.
    describe 'the README section the table feeds' do
      let(:filterable) do
        File.read(File.expand_path('../../../README.md', __dir__), encoding: 'UTF-8')[
          /### What is filterable\n(.*?)\n### /m, 1
        ]
      end

      it 'lists exactly the columns each endpoint filters' do
        { 'IntercomConversation' => 'conversations', 'IntercomTicket' => 'tickets' }.each do |collection, endpoint|
          row = filterable.lines.find { |line| line.start_with?("| `#{collection}` |") }
          listed = row.to_s.scan(/`([a-z_]+)`/).flatten

          expect(listed).to match_array(described_class.fetch(endpoint).filterable_columns)
        end
      end
    end

    describe 'a table that cannot be trusted' do
      it 'refuses an operator Intercom has no spelling for' do
        expect { table(fields: { 'created_at' => field_row('operators' => ['~=']) }) }
          .to raise_error(ConfigurationError, /has no operator ~=/)
      end

      it 'refuses a type nothing knows how to send' do
        expect { table(fields: { 'created_at' => field_row('type' => 'timestamp') }) }
          .to raise_error(ConfigurationError, /type "timestamp" is not one of/)
      end

      # An empty list would publish a filterable column no operator can reach.
      it 'refuses a field declaring no operator, and says where it belongs' do
        expect { table(fields: { 'created_at' => field_row('operators' => []) }) }
          .to raise_error(ConfigurationError, /belongs in the refused table/)
      end

      it 'refuses a provenance that is neither measured nor read off the documentation' do
        expect { table(fields: { 'created_at' => field_row('source' => 'guessed') }) }
          .to raise_error(ConfigurationError, /source "guessed" is neither measured nor spec/)
      end

      it 'refuses a refusal with no provenance of its own' do
        expect { table(refused: { 'company_id' => { 'reason' => 'no', 'source' => 'hearsay' } }) }
          .to raise_error(ConfigurationError, /tickets.company_id/)
      end

      it 'names the endpoint and the column it choked on' do
        expect { table(fields: { 'created_at' => field_row('type' => 'timestamp') }) }
          .to raise_error(ConfigurationError, /search_fields\.yml is malformed at tickets\.created_at/)
      end
    end

    describe 'what it hands to the schema' do
      it 'carries the Intercom field a column is filtered through' do
        expect(described_class.fetch('conversations').field('closed_at').field).to eq('statistics.last_close_at')
      end

      it 'reads a refusal reason as one line, whatever the YAML wrapping' do
        reason = table(refused: { 'company_id' => { 'reason' => "one\ntwo\n", 'source' => 'spec' } })
                 .refusal('company_id').reason

        expect(reason).to eq('one two')
      end

      it 'refuses an endpoint nothing declares, rather than filtering nothing' do
        expect { described_class.fetch('contacts') }
          .to raise_error(ConfigurationError, /Unknown Intercom search endpoint "contacts"/)
      end

      it 'is measured once the probe has stamped a date on it' do
        expect(table(measured_at: '2026-09-01')).to be_measured
      end
    end
  end
end
