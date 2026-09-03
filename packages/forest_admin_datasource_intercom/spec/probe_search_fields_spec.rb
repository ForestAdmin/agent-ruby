require 'tmpdir'

load File.expand_path('../bin/probe_search_fields', __dir__)

module ForestAdminDatasourceIntercom
  RSpec.describe ProbeSearchFields do
    let(:base) { Configuration::REGION_HOSTS[:us] }
    let(:endpoint) { Query::SearchFields.fetch('tickets') }
    let(:client) { Client.new(Configuration.new(access_token: 's3cr3t', rate_limiter: nil)) }

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    # Every probe is a search asking for one record; what a stub answers is
    # therefore an empty page or one of Intercom's refusal codes.
    def stub_search(code: nil, operator: nil, value: nil)
      body = if code
               { 'type' => 'error.list', 'errors' => [{ 'code' => code, 'message' => 'nope' }] }
             else
               { 'type' => 'list', 'tickets' => [], 'total_count' => 0 }
             end

      stub_request(:post, "#{base}/tickets/search").with { |request| matches?(request, operator, value) }
                                                   .to_return(json(body, code ? 400 : 200))
    end

    def matches?(request, operator, value)
      query = JSON.parse(request.body)['query']

      (operator.nil? || query['operator'] == operator) && (value.nil? || query['value'] == value)
    end

    describe 'the type guessed for a candidate field' do
      # A candidate is a name and nothing else -- discovering what it is is the
      # point -- so the value shape sent with it is guessed from that name.
      it 'reads a timestamp, a count and a flag off the name' do
        expect(described_class.guess_type('statistics.last_close_at')).to eq('date')
        expect(described_class.guess_type('count_reopens')).to eq('number')
        expect(described_class.guess_type('open')).to eq('boolean')
        expect(described_class.guess_type('state')).to eq('string')
      end
    end

    describe described_class::Probe do
      subject(:probe) { described_class.new(client, endpoint) }

      it 'keeps the operators the endpoint answers and drops the ones it refuses' do
        stub_search(code: 'data_invalid')
        stub_search(operator: '=')
        stub_search(operator: '!=')

        result = probe.run('category', 'string')

        expect(result[:operators].select { |_, outcome| outcome[:ok] }.keys).to eq(['=', '!='])
      end

      # A field the endpoint does not filter at all is worth one request, not
      # twelve: `invalid_field` ends the row.
      it 'stops at the first invalid_field and reports the field unfilterable' do
        stub_search(code: 'invalid_field')

        result = probe.run('company_id', 'string')

        expect(result[:unfilterable][:code]).to eq('invalid_field')
        expect(a_request(:post, "#{base}/tickets/search")).to have_been_made.once
      end

      # A wrong value shape is refused with the same code as an unsupported
      # operator, so a single attempt would report a filter Intercom does answer
      # as refused.
      it 'retries a refused cell with the other value shapes its type takes' do
        stub_search(code: 'data_invalid')
        stub_search(operator: '>', value: '2026-01-01')

        result = probe.run('created_at', 'date')

        expect(result[:operators]['>'][:ok]).to be(true)
        expect(result[:operators]['<'][:ok]).to be(false)
      end

      it 'names the failure by its HTTP status when Intercom sends no error code' do
        stub_request(:post, "#{base}/tickets/search").to_return(json({ 'nope' => true }, 500))

        result = probe.run('category', 'string')

        expect(result[:operators]['='][:code]).to eq('http_500')
      end
    end

    describe described_class::Report do
      subject(:report) { described_class.new(endpoint) }

      def run_probe(field, type)
        ProbeSearchFields::Probe.new(client, endpoint).run(field, type)
      end

      # The only reason to run the probe: an operator the table promises and
      # Intercom refuses is a filter the interface offers and the read cannot
      # honour.
      it 'reports an operator the table promises and Intercom refuses' do
        stub_search(code: 'data_invalid')
        stub_search(operator: '=')
        report.record('category', 'category', run_probe('category', 'string'))

        expect { report.print_diff }.to output(/! the table promises != here, Intercom refuses it/).to_stdout
      end

      it 'reports an operator the table does not know about yet' do
        stub_search(code: 'data_invalid')
        ['=', '!=', '~'].each { |operator| stub_search(operator: operator) }
        report.record('category', 'category', run_probe('category', 'string'))

        expect { report.print_diff }.to output(/\+ Intercom also accepts ~/).to_stdout
      end

      it 'names the column a field the endpoint refuses is declared on' do
        stub_search(code: 'invalid_field')
        report.record('category', 'category', run_probe('category', 'string'))

        expect { report.print_diff }.to output(/NOT FILTERABLE \(invalid_field\).*column 'category'/).to_stdout
      end

      it 'writes the measurement as evidence, refusal codes included' do
        stub_search(code: 'data_invalid')
        stub_search(operator: '=')
        report.record('category', 'category', run_probe('category', 'string'))

        written = YAML.safe_load(report.to_yaml_document)

        expect(written['fields']['category']['operators']).to eq(['='])
        expect(written['fields']['category']['refused']['!=']).to eq('data_invalid')
      end

      it 'writes a field the endpoint refuses as unfilterable' do
        stub_search(code: 'invalid_field')
        report.record('company_id', nil, run_probe('company_id', 'string'))

        written = YAML.safe_load(report.to_yaml_document)

        expect(written['fields']['company_id']).to eq({ 'filterable' => false, 'code' => 'invalid_field' })
      end
    end

    describe described_class::CLI do
      # A probe with no token would abort on the first request with an Intercom
      # 401, which reads as a workspace problem rather than as a missing option.
      it 'refuses to start without a token' do
        expect { described_class.call(['--endpoint', 'tickets']) }
          .to raise_error(SystemExit).and output(/No token/).to_stderr
      end

      it 'refuses an endpoint the table does not declare' do
        expect { described_class.call(['--endpoint', 'contacts', '--token', 's3cr3t']) }
          .to raise_error(ConfigurationError, /Unknown Intercom search endpoint/)
      end

      it 'probes every declared endpoint and writes the evidence where it was asked to' do
        out = File.join(Dir.tmpdir, 'intercom-probe.yml')
        stub_search(code: 'invalid_field')
        stub_request(:post, "#{base}/conversations/search")
          .to_return(json({ 'type' => 'error.list', 'errors' => [{ 'code' => 'invalid_field' }] }, 400))

        expect { described_class.call(['--token', 's3cr3t', '--out', out]) }.to output(/NOT FILTERABLE/).to_stdout
        expect(YAML.safe_load_file(out)['endpoint']).to eq('conversations')
      ensure
        FileUtils.rm_f(out)
      end
    end
  end
end
