require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Services
    include ForestAdminAgent::Http::Exceptions
    include ForestAdminAgent::Utils
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query

    describe SmartActionChecker do
      include_context 'with caller'

      let :args do
        {
          headers: {
            'HTTP_AUTHORIZATION' => bearer
          },
          params: {
            'timezone' => 'Europe/Paris'
          }
        }
      end

      let :parameters do
        {
          data: {
            attributes: {
              values: [],
              ids: [1],
              collection_name: 'Booking',
              parent_collection_name: nil,
              parent_collection_id: nil,
              parent_association_name: nil,
              all_records: false,
              all_records_subset_query: {
                'fields[Book]' => 'id,title',
                'page[number]' => 1,
                'page[size]' => 15,
                'sort' => '-id',
                'timezone' => 'Europe/Paris'
              },
              all_records_ids_excluded: [],
              smart_action_id: 'Booking-Mark@@@as@@@live',
              signed_approval_request: nil
            },
            type: 'custom-action-requests'
          }
        }
      end

      let :smart_action do
        {
          triggerEnabled: [],
          triggerConditions: [],
          approvalRequired: [],
          approvalRequiredConditions: [],
          userApprovalEnabled: [],
          userApprovalConditions: [],
          selfApprovalEnabled: []
        }
      end

      before do
        @datasource = Datasource.new
        collection_book = instance_double(
          Collection,
          name: 'Book',
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'title' => ColumnSchema.new(column_type: 'String')
          }
        )

        allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
        @datasource.add_collection(collection_book)
        ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
        ForestAdminAgent::Builder::AgentFactory.instance.build
      end

      it 'returns true when the user can trigger the action' do
        smart_action[:triggerEnabled] = [1]

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'returns true when the user can trigger the action with trigger conditions' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:triggerConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'title',
                  'value' => nil,
                  'source' => 'data',
                  'operator' => 'present'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return([{ 'value' => 1, 'group' => [] }])

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'returns true when the user can trigger the action with trigger conditions with all_records_ids_excluded not empty' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:triggerConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'title',
                  'value' => nil,
                  'source' => 'data',
                  'operator' => 'present'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        parameters[:data][:attributes][:all_records_ids_excluded] = [1]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return([{ 'value' => 1, 'group' => [] }])

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'throws when the user try to trigger the action with approvalRequired and without approvalRequiredConditions' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:approvalRequired] = [1]
        smart_action[:approvalRequiredConditions] = []

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(RequireApproval, 'This action requires to be approved.')
      end

      it 'throws when the user try to trigger the action with approvalRequired and match approvalRequiredConditions' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:approvalRequired] = [1]
        smart_action[:approvalRequiredConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return([{ 'value' => 1, 'group' => [] }])

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(RequireApproval, 'This action requires to be approved.')
      end

      it 'returns true when the user try to trigger the action with approvalRequired and triggerConditions and correct role into approvalRequired' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:approvalRequired] = [1]
        smart_action[:approvalRequiredConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return([{ 'value' => 0, 'group' => [] }])

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'returns true when the user try to trigger the action with approvalRequired with triggerConditions and correct role into approvalRequired' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:triggerConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'title',
                  'value' => nil,
                  'source' => 'data',
                  'operator' => 'present'
                }
              ]
            },
            'roleId' => 1
          }
        ]
        smart_action[:approvalRequired] = [1]
        smart_action[:approvalRequiredConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 0, 'group' => [] }],
          [{ 'value' => 1, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'throws when the user roleId is not into triggerEnabled & approvalRequired' do
        smart_action[:triggerEnabled] = [1000]
        smart_action[:triggerConditions] = []
        smart_action[:approvalRequired] = [1000]
        smart_action[:approvalRequiredConditions] = []

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError,
                           "You don't have the permission to trigger this action.")
      end

      it "throws when smart action doesn't match with triggerConditions & approvalRequiredConditions" do
        smart_action[:triggerEnabled] = [1]
        smart_action[:triggerConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'title',
                  'value' => nil,
                  'source' => 'data',
                  'operator' => 'present'
                }
              ]
            },
            'roleId' => 1
          }
        ]
        smart_action[:approvalRequired] = [1]
        smart_action[:approvalRequiredConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 0, 'group' => [] }],
          [{ 'value' => 0, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError,
                           "You don't have the permission to trigger this action.")
      end

      it 'returns true when the user can approve and there is no userApprovalConditions and requesterId is not the callerId' do
        parameters[:data][:attributes][:requester_id] = 20
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalEnabled] = [1]

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'returns true when the user can approve and there is no userApprovalConditions and user roleId is present into selfApprovalEnabled' do
        parameters[:data][:attributes][:requester_id] = 1
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalEnabled] = [1]
        smart_action[:selfApprovalEnabled] = [1]

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'returns true when the user can approve and the condition match with userApprovalConditions and requesterId is the callerId' do
        parameters[:data][:attributes][:requester_id] = 20
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalEnabled] = [1]
        smart_action[:userApprovalConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 1, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'returns true when the user can approve and the condition match with userApprovalConditions and user roleId is present into selfApprovalEnabled' do
        parameters[:data][:attributes][:requester_id] = 1
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalEnabled] = [1]
        smart_action[:userApprovalConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]
        smart_action[:selfApprovalEnabled] = [1]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 1, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect(smart_action_checker).to be_can_execute
      end

      it 'throws when the user try to approve when there is no userApprovalConditions and requesterId is equal to the callerId' do
        parameters[:data][:attributes][:requester_id] = 1
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError,
                           'You don\'t have the permission to trigger this action.')
      end

      it 'throws when the user try to approve and there is no userApprovalConditions and user roleId is not present into selfApprovalEnabled' do
        parameters[:data][:attributes][:requester_id] = 1
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:selfApprovalEnabled] = [1000]

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError,
                           'You don\'t have the permission to trigger this action.')
      end

      it "throws when the user try to approve and the condition don't match with userApprovalConditions and requesterId is the callerId" do
        parameters[:data][:attributes][:requester_id] = 1
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 1, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError,
                           'You don\'t have the permission to trigger this action.')
      end

      it "throws when the user try to approve and the condition don't match with userApprovalConditions and requesterId is not the callerId" do
        parameters[:data][:attributes][:requester_id] = 20
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1000,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 0, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError, "You don't have the permission to trigger this action.")
      end

      it "throws when the user try to approve and the condition don't match with userApprovalConditions and user roleId is not present into selfApprovalEnabled" do
        parameters[:data][:attributes][:requester_id] = 1
        parameters[:data][:attributes][:signed_approval_request] = 'AAABBBCCC'
        smart_action[:userApprovalConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'id',
                  'value' => 1000,
                  'source' => 'data',
                  'operator' => 'equal'
                }
              ]
            },
            'roleId' => 1
          }
        ]
        smart_action[:selfApprovalEnabled] = [1000]

        collection = @datasource.get_collection('Book')
        allow(collection).to receive(:aggregate).and_return(
          [{ 'value' => 0, 'group' => [] }]
        )

        smart_action_checker = described_class.new(parameters, collection, smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)
        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ForbiddenError,
                           "You don't have the permission to trigger this action.")
      end

      it 'throws with an unknown operators' do
        smart_action[:triggerEnabled] = [1]
        smart_action[:triggerConditions] = [
          {
            'filter' => {
              'aggregator' => 'and',
              'conditions' => [
                {
                  'field' => 'title',
                  'value' => nil,
                  'source' => 'data',
                  'operator' => 'unknown'
                }
              ]
            },
            'roleId' => 1
          }
        ]

        smart_action_checker = described_class.new(parameters, @datasource.get_collection('Book'), smart_action,
                                                   QueryStringParser.parse_caller(args), 1, Filter.new)

        expect do
          smart_action_checker.can_execute?
        end.to raise_error(ConflictError,
                           'The conditions to trigger this action cannot be verified. Please contact an administrator.')
      end
    end
  end
end
