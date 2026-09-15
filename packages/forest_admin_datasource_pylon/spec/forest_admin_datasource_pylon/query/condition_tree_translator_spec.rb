module ForestAdminDatasourcePylon
  RSpec.describe Query::ConditionTreeTranslator do
    def leaf(field, operator, value = nil)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    # Nests `depth` multi-condition branches: the outermost sits at depth 1, so
    # the innermost branch sits at depth `depth`.
    def nested(depth)
      (1..depth).reduce(leaf('state', operators::EQUAL, 'new')) do |tree, _|
        branch('And', [tree, leaf('team_id', operators::EQUAL, 'team-1')])
      end
    end

    def translate(tree, api_filters: default_filters, timezone: nil)
      described_class.call(tree, api_filters: api_filters, timezone: timezone)
    end

    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:default_filters) { Collections::Issue::ApiFilters::API_FILTERS }

    it 'translates a nil condition tree to no filter' do
      expect(translate(nil)).to be_nil
    end

    it 'rejects a node that is neither a leaf nor a branch' do
      expect { translate(Object.new) }
        .to raise_error(UnsupportedOperatorError, /Unknown condition node/)
    end

    describe 'equality operators' do
      it 'translates equal to a single-valued equals' do
        expect(translate(leaf('state', operators::EQUAL, 'new')))
          .to eq('field' => 'state', 'operator' => 'equals', 'value' => 'new')
      end

      it 'translates in and not_in to a values list' do
        expect(translate(leaf('state', operators::IN, %w[new closed])))
          .to eq('field' => 'state', 'operator' => 'in', 'values' => %w[new closed])
        expect(translate(leaf('state', operators::NOT_IN, %w[closed])))
          .to eq('field' => 'state', 'operator' => 'not_in', 'values' => %w[closed])
      end

      # The toolkit rewrites not_equal into not_in, so the translator never has
      # to spell the same filter twice.
      it 'refuses not_equal, which the toolkit derives from not_in' do
        expect { translate(leaf('state', operators::NOT_EQUAL, 'new')) }
          .to raise_error(UnsupportedOperatorError, /Supported: equal, in, not_in/)
      end
    end

    describe 'presence operators' do
      it 'translates present and blank without carrying a value' do
        expect(translate(leaf('assignee_id', operators::PRESENT)))
          .to eq('field' => 'assignee_id', 'operator' => 'is_set')
        expect(translate(leaf('assignee_id', operators::BLANK)))
          .to eq('field' => 'assignee_id', 'operator' => 'is_unset')
      end

      # Left out of the map, `missing` is rewritten by the toolkit into
      # `equal nil`, which no Pylon operator expresses: the field would refuse
      # the very absence check it is one of the few to accept.
      it 'translates missing to the same is_unset as blank' do
        expect(translate(leaf('assignee_id', operators::MISSING)))
          .to eq('field' => 'assignee_id', 'operator' => 'is_unset')
      end

      # Pylon lists is_set / is_unset for the party ids and issue_type only.
      it 'refuses presence on a field Pylon does not accept it for' do
        expect { translate(leaf('state', operators::PRESENT)) }
          .to raise_error(UnsupportedOperatorError, /Operator 'present' is not supported on field 'state'/)
      end
    end

    describe 'text operators' do
      it 'maps both spellings of contains onto the single Pylon substring operator' do
        expect(translate(leaf('title', operators::CONTAINS, 'boom')))
          .to eq('field' => 'title', 'operator' => 'string_contains', 'value' => 'boom')
        expect(translate(leaf('body_html', operators::I_CONTAINS, 'boom')))
          .to eq('field' => 'body_html', 'operator' => 'string_contains', 'value' => 'boom')
      end

      # Symmetrically with contains: Pylon documents no case semantics for its
      # single substring operator, so leaving not_i_contains out would offer a
      # case-insensitive "contains" the UI could not negate.
      it 'maps both spellings of not_contains onto the single negated operator' do
        expect(translate(leaf('title', operators::NOT_CONTAINS, 'boom')))
          .to eq('field' => 'title', 'operator' => 'string_does_not_contain', 'value' => 'boom')
        expect(translate(leaf('body_html', operators::NOT_I_CONTAINS, 'boom')))
          .to eq('field' => 'body_html', 'operator' => 'string_does_not_contain', 'value' => 'boom')
      end

      # A bare date is read off the operator, not off the shape of the string: a
      # text field holding what looks like a date holds a value of its own.
      it 'leaves a date-shaped value untouched on a field not compared as time' do
        expect(translate(leaf('title', operators::I_CONTAINS, '2026-08-01')))
          .to include('value' => '2026-08-01')
      end

      it 'refuses equal on a text field, which Pylon cannot match exactly' do
        expect { translate(leaf('title', operators::EQUAL, 'Boom')) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'title'/)
      end

      # `tags` holds a list, so membership is matched against candidates rather
      # than compared.
      it 'translates tag membership with the list operators' do
        expect(translate(leaf('tags', operators::IN, %w[urgent vip])))
          .to eq('field' => 'tags', 'operator' => 'in', 'values' => %w[urgent vip])
        expect(translate(leaf('tags', operators::NOT_IN, %w[urgent])))
          .to eq('field' => 'tags', 'operator' => 'not_in', 'values' => %w[urgent])
      end

      # Pylon accepts `contains` on a list field, and the map leaves it out: the
      # column is typed Json, on which the toolkit refuses the operator before
      # the translator ever sees it.
      it 'refuses the substring operators on a list column' do
        expect { translate(leaf('tags', operators::CONTAINS, 'urgent')) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'tags'/)
      end
    end

    describe 'time operators' do
      it 'translates the bare comparisons to the time bounds' do
        expect(translate(leaf('created_at', operators::GREATER_THAN, '2026-08-01T00:00:00Z')))
          .to eq('field' => 'created_at', 'operator' => 'time_is_after', 'value' => '2026-08-01T00:00:00Z')
        expect(translate(leaf('updated_at', operators::LESS_THAN, '2026-08-01T00:00:00Z')))
          .to eq('field' => 'updated_at', 'operator' => 'time_is_before', 'value' => '2026-08-01T00:00:00Z')
      end

      it 'formats a Time value as an UTC timestamp' do
        expect(translate(leaf('created_at', operators::GREATER_THAN, Time.utc(2026, 8, 7, 13, 6, 22))))
          .to include('value' => '2026-08-07T13:06:22Z')
      end

      it 'reads a bare Date as midnight in the timezone of the caller' do
        filter = translate(leaf('created_at', operators::GREATER_THAN, Date.new(2026, 8, 7)),
                           timezone: 'Europe/Paris')

        expect(filter).to include('value' => '2026-08-06T22:00:00Z')
      end

      # Kept as it came, a padded identifier passes the blank guard and then
      # fails the zone lookup, and the bound falls back to UTC -- a day boundary
      # off by the offset, which is what the guard exists to prevent.
      it 'reads a timezone carrying whitespace as the zone it names' do
        filter = translate(leaf('created_at', operators::GREATER_THAN, Date.new(2026, 8, 7)),
                           timezone: '  Europe/Paris  ')

        expect(filter).to include('value' => '2026-08-06T22:00:00Z')
      end

      # Declaring only the bare comparisons on a Date column is enough: the
      # toolkit rewrites every interval operator into the pair of bounds Pylon
      # accepts, which is also why `time_range` never has to be emitted.
      it 'translates an interval operator the toolkit rewrote into a pair of bounds' do
        equivalent = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent
                     .get_equivalent_tree(leaf('created_at', operators::TODAY),
                                          Collections::Issue::ApiFilters.forest_operators('created_at'),
                                          'Date', 'UTC')

        filter = translate(equivalent)

        expect(filter['operator']).to eq('and')
        expect(filter['subfilters'].map { |sub| sub['operator'] }).to eq(%w[time_is_after time_is_before])
      end

      # A Dateonly column -- only a custom field is typed that way -- sends the
      # date alone, where every native column sends `time_is_after` a timestamp.
      # The bound is the one a Ruby Date already gets.
      it 'reads a bare date string as midnight in the timezone of the caller' do
        filter = translate(leaf('created_at', operators::GREATER_THAN, '2026-08-01'), timezone: 'Europe/Paris')

        expect(filter).to include('value' => '2026-07-31T22:00:00Z')
      end

      it 'leaves a string no date can be read from to Pylon, which names what it refuses' do
        expect(translate(leaf('created_at', operators::GREATER_THAN, '2026-13-45')))
          .to include('value' => '2026-13-45')
      end

      it 'falls back to UTC and warns on a timezone it does not know' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)

        filter = translate(leaf('created_at', operators::GREATER_THAN, Date.new(2026, 8, 7)),
                           timezone: 'Moon/Base')

        expect(filter).to include('value' => '2026-08-07T00:00:00Z')
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(%r{unknown timezone 'Moon/Base'})
      end
    end

    # An issue is read with `type` / `resolution_time` / `latest_message_time`
    # but filtered on the names below.
    describe 'field renames' do
      it 'renames the columns Pylon spells differently in a filter' do
        expect(translate(leaf('type', operators::EQUAL, 'ticket'))).to include('field' => 'issue_type')
        expect(translate(leaf('resolution_time', operators::GREATER_THAN, '2026-08-01T00:00:00Z')))
          .to include('field' => 'resolved_at')
        expect(translate(leaf('latest_message_time', operators::LESS_THAN, '2026-08-01T00:00:00Z')))
          .to include('field' => 'latest_message_activity_at')
      end
    end

    describe 'branches' do
      it 'translates an and into nested sub-filters' do
        tree = branch('And', [leaf('state', operators::EQUAL, 'new'), leaf('team_id', operators::EQUAL, 'team-1')])

        expect(translate(tree)).to eq(
          'operator' => 'and',
          'subfilters' => [{ 'field' => 'state', 'operator' => 'equals', 'value' => 'new' },
                           { 'field' => 'team_id', 'operator' => 'equals', 'value' => 'team-1' }]
        )
      end

      # Pylon nests sub-filters, so OR is expressed natively instead of being
      # rejected the way the Zendesk query string forces.
      it 'translates an or natively' do
        tree = branch('Or', [leaf('state', operators::EQUAL, 'new'), leaf('title', operators::CONTAINS, 'boom')])

        expect(translate(tree)['operator']).to eq('or')
        expect(translate(tree)['subfilters'].size).to eq(2)
      end

      it 'unwraps a branch carrying a single condition' do
        tree = branch('And', [leaf('state', operators::EQUAL, 'new')])

        expect(translate(tree)).to eq('field' => 'state', 'operator' => 'equals', 'value' => 'new')
      end

      it 'accepts sub-filters nested up to the depth Pylon allows' do
        expect(translate(nested(3))).to include('operator' => 'and')
      end

      it 'refuses sub-filters nested deeper than Pylon allows' do
        expect { translate(nested(4)) }
          .to raise_error(UnsupportedOperatorError, /nested deeper than 3 levels/)
      end

      it 'refuses a branch carrying no condition' do
        expect { translate(branch('And', [])) }
          .to raise_error(UnsupportedOperatorError, /carries no condition/)
      end

      it 'refuses an aggregator it does not know' do
        tree = branch('Xor', [leaf('state', operators::EQUAL, 'new'), leaf('team_id', operators::EQUAL, 'team-1')])

        expect { translate(tree) }.to raise_error(UnsupportedOperatorError, /Unknown condition tree aggregator/)
      end

      # The toolkit validates no aggregator, so the unwrap is the one place an
      # unknown one could have slipped through unnoticed.
      it 'refuses an aggregator it does not know even when it carries a lone condition' do
        expect { translate(branch('Xor', [leaf('state', operators::EQUAL, 'new')])) }
          .to raise_error(UnsupportedOperatorError, /Unknown condition tree aggregator/)
      end
    end

    describe 'guards' do
      it 'refuses a field Pylon cannot filter on' do
        expect { translate(leaf('number', operators::EQUAL, 12)) }
          .to raise_error(UnsupportedOperatorError, /Pylon cannot filter on 'number'/)
      end

      # An empty list would translate to a filter matching everything, turning
      # "match nothing" into its exact opposite.
      it 'refuses an empty list of values' do
        expect { translate(leaf('state', operators::IN, [])) }
          .to raise_error(UnsupportedOperatorError, /was given an empty list/)
      end

      # Dropping the blanks would answer a different question: `not_in [nil,
      # 'open']` was asked to exclude the blank records, and a narrowed
      # `not_in ['open']` comes back including them.
      it 'refuses a list holding a blank value rather than narrowing it' do
        expect { translate(leaf('state', operators::IN, [nil, 'open'])) }
          .to raise_error(UnsupportedOperatorError, /holding a blank value/)
        expect { translate(leaf('state', operators::NOT_IN, ['open', ''])) }
          .to raise_error(UnsupportedOperatorError, /holding a blank value/)
      end

      # The agent advertises `present`, `blank` and `missing` on every field
      # carrying an equality filter, and rewrites them into `not_in [nil, '']`,
      # `in [nil, '']` and `equal nil`. On a field Pylon accepts no is_set /
      # is_unset on, the refusal has to name the absence filter the operator set
      # rather than the empty value it was rewritten into.
      it 'refuses an absence filter on a field carrying no presence operator' do
        expect { translate(leaf('state', operators::IN, [nil, ''])) }
          .to raise_error(UnsupportedOperatorError, /cannot filter 'state' for absence/)
        expect { translate(leaf('state', operators::NOT_IN, [nil, ''])) }
          .to raise_error(UnsupportedOperatorError, /cannot filter 'state' for absence/)
        expect { translate(leaf('state', operators::EQUAL, nil)) }
          .to raise_error(UnsupportedOperatorError, /cannot filter 'state' for absence/)
      end

      # `assignee_id` does carry is_set / is_unset, so a nil reaching the value
      # comes from a scope or a segment written in Ruby rather than from a
      # rewritten absence filter: the message names the operators to write it
      # with instead.
      it 'points a nil on a presence-filtered field at the presence operators' do
        expect { translate(leaf('assignee_id', operators::EQUAL, nil)) }
          .to raise_error(UnsupportedOperatorError, /use the PRESENT or BLANK operator/)
        expect { translate(leaf('assignee_id', operators::IN, [nil, ''])) }
          .to raise_error(UnsupportedOperatorError, /holding a blank value/)
      end

      it 'refuses every filter when the collection declares none' do
        expect { translate(leaf('state', operators::EQUAL, 'new'), api_filters: {}) }
          .to raise_error(UnsupportedOperatorError, /Pylon cannot filter on 'state'/)
      end
    end

    # The filter travels as JSON, so only the date types need a wire format.
    describe 'value types' do
      let(:default_filters) do
        { 'number_of_touches' => { ops: { operators::EQUAL => 'equals', operators::IN => 'in' } },
          'customer_portal_visible' => { ops: { operators::EQUAL => 'equals' } } }
      end

      it 'passes numbers and booleans through untouched' do
        expect(translate(leaf('number_of_touches', operators::EQUAL, 12))).to include('value' => 12)
        expect(translate(leaf('customer_portal_visible', operators::EQUAL, false)))
          .to include('value' => false)
      end

      # The agent casts every Number column with `to_f`, so an integer custom
      # field would be filtered with `42.0` -- a form none of its values carry.
      # `be` rather than `eq`: `12.0 == 12` holds in Ruby, and the form that
      # travels to Pylon is the one thing this is about.
      it 'sends an integer-valued float as the integer it is' do
        expect(translate(leaf('number_of_touches', operators::EQUAL, 12.0))['value']).to be(12)
      end

      it 'keeps what a decimal carries after the point' do
        expect(translate(leaf('number_of_touches', operators::EQUAL, 12.5))['value']).to be(12.5)
      end

      # `"1e999".to_f` is what the agent's own cast hands over. Left alone it
      # reaches `to_i`, which raises, and then the JSON encoder, which raises
      # too -- a 500 either way, on a value the operator typed.
      it 'refuses a value the cast overflowed rather than raising on it' do
        expect { translate(leaf('number_of_touches', operators::EQUAL, '1e999'.to_f)) }
          .to raise_error(ForestAdminDatasourcePylon::UnsupportedOperatorError, /number_of_touches.*Infinity/m)
      end

      it 'refuses a NaN the same way' do
        expect { translate(leaf('number_of_touches', operators::EQUAL, Float::NAN)) }
          .to raise_error(ForestAdminDatasourcePylon::UnsupportedOperatorError, /number_of_touches.*NaN/m)
      end

      it 'refuses one inside a list too, the list being formatted the same way' do
        expect(translate(leaf('number_of_touches', operators::IN, [1.0, 2.5]))['values']).to eq([1, 2.5])
        expect { translate(leaf('number_of_touches', operators::IN, [1.0, -Float::INFINITY])) }
          .to raise_error(ForestAdminDatasourcePylon::UnsupportedOperatorError, /number_of_touches.*-Infinity/m)
      end
    end
  end
end
