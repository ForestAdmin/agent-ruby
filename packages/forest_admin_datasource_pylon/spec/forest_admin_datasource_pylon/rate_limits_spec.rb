RSpec.describe ForestAdminDatasourcePylon::RateLimits do
  def rule_for(method, path) = described_class.for(method, path)

  describe '.for' do
    it 'reads the documented budget of the search endpoints' do
      expect(rule_for(:post, '/issues/search').limit).to eq(120)
      expect(rule_for(:post, '/accounts/search').limit).to eq(120)
      expect(rule_for(:post, '/contacts/search').limit).to eq(120)
    end

    it 'reads the documented budget of the single-record reads' do
      expect(rule_for(:get, '/issues/abc-123').limit).to eq(300)
      expect(rule_for(:get, '/accounts/acc_1').limit).to eq(300)
      expect(rule_for(:get, '/contacts/con_1').limit).to eq(300)
      expect(rule_for(:get, '/users/usr_1').limit).to eq(300)
      expect(rule_for(:get, '/teams/team_1').limit).to eq(300)
    end

    it 'reads the documented budget of the unpaginated lists' do
      expect(rule_for(:get, '/users').limit).to eq(300)
      expect(rule_for(:get, '/teams').limit).to eq(300)
      expect(rule_for(:get, '/custom-fields').limit).to eq(300)
    end

    it 'reads the documented budget of the writes' do
      expect(rule_for(:post, '/issues').limit).to eq(30)
      expect(rule_for(:patch, '/issues/abc').limit).to eq(120)
    end

    # `/issues/{id}` and `/issues/{id}/messages` sit under the same prefix at
    # budgets differing by a factor of two and a half, so a rule matching the
    # prefix would meter the thread against the wrong window.
    it 'tells a nested endpoint from the record it hangs off' do
      expect(rule_for(:get, '/issues/abc/messages').limit).to eq(120)
      expect(rule_for(:get, '/issues/abc').limit).to eq(300)
    end

    # GET /issues is documented at a tenth of GET /issues/{id}: the verb is the
    # same and the path differs by one segment, which is the whole difference.
    it 'tells a collection endpoint from a record endpoint' do
      expect(rule_for(:get, '/issues').limit).to eq(30)
      expect(rule_for(:get, '/issues/abc').limit).to eq(300)
    end

    # Reading an issue is granted two and a half times what patching it is, so a
    # table keyed on the path alone would meter one of the two wrong.
    it 'tells one verb from another on the same path' do
      expect(rule_for(:get, '/issues/abc').limit).to eq(300)
      expect(rule_for(:patch, '/issues/abc').limit).to eq(120)
    end

    describe 'the bucket a rule names' do
      # Pylon meters per endpoint, so two endpoints sharing a figure must not
      # share a window: pooling them would throttle at half the granted budget.
      it 'is distinct for two endpoints at the same budget' do
        expect(rule_for(:get, '/users').name).not_to eq(rule_for(:get, '/teams').name)
      end

      it 'is the same for two records of one endpoint' do
        expect(rule_for(:get, '/issues/one').name).to eq(rule_for(:get, '/issues/two').name)
      end
    end

    describe 'an endpoint the API reference does not rate' do
      it 'falls back to the lowest budget documented anywhere' do
        expect(rule_for(:get, '/me').limit).to eq(described_class::DEFAULT_LIMIT)
        expect(rule_for(:delete, '/issues/abc').limit).to eq(described_class::DEFAULT_LIMIT)
      end

      it 'says so in the name, so a log line does not read as a documented budget' do
        expect(rule_for(:get, '/me').name).to match(/undocumented/)
      end

      # Keying the fallback on the path would open a window per record id, so a
      # fan-out over a hundred records would meter as a hundred endpoints one
      # request in — that is, as no limit at all.
      it 'buckets by endpoint rather than by record' do
        expect(rule_for(:delete, '/issues/one').name).to eq(rule_for(:delete, '/issues/two').name)
      end

      it 'keeps two undocumented verbs on one path apart' do
        expect(rule_for(:delete, '/accounts/x').name).not_to eq(rule_for(:put, '/accounts/x').name)
      end
    end

    describe 'the shape of the path it is handed' do
      it 'accepts a string or a symbol verb' do
        expect(rule_for('POST', '/issues/search').limit).to eq(120)
        expect(rule_for(:post, '/issues/search').limit).to eq(120)
      end

      it 'ignores a trailing slash' do
        expect(rule_for(:get, '/users/').limit).to eq(300)
      end

      it 'tolerates a path Faraday hands over without its leading slash' do
        expect(rule_for(:get, 'users').limit).to eq(300)
      end
    end
  end

  describe 'DEFAULT_LIMIT' do
    # The fallback is only conservative if nothing documented sits below it.
    it 'is no higher than the lowest rule in the table' do
      expect(described_class::DEFAULT_LIMIT).to be <= described_class::RULES.map { |_v, _p, r| r.limit }.min
    end
  end
end
