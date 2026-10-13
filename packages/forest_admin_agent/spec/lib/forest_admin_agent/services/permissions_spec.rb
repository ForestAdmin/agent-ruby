require 'spec_helper'

require 'faraday'
require 'filecache'

module ForestAdminAgent
  module Services
    include ForestAdminAgent::Utils
    include ForestAdminAgent::Http::Exceptions
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Exceptions

    describe Permissions do
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
      let(:forest_api_requester) { instance_double(ForestAdminAgent::Http::ForestAdminApiRequester) }
      let(:role_id) { 1 }
      let(:user_role_id) { 1 }

      before do
        # clear main cache
        cache = FileCache.new('app', 'tmp/cache/forest_admin')
        cache.clear

        @datasource = Datasource.new
        collection_book = instance_double(
          Collection,
          name: 'Book',
          fields: {
            'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
            'title' => ColumnSchema.new(column_type: 'String')
          },
          actions: {
            'make-photocopy' => {
              scope: 'Single',
              execute: nil
            }
          }
        )

        @datasource.add_collection(collection_book)
        agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
        agent_factory.setup(
          {
            auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
            env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
            is_production: false,
            cache_dir: 'tmp/cache/forest_admin',
            schema_path: "#{__dir__}/../../../shared/.forestadmin-schema.json",
            forest_server_url: 'https://api.development.forestadmin.com',
            debug: true,
            prefix: 'forest',
            permission_expiration: 100,
            customize_error_message: nil
          }
        )

        agent_factory.add_datasource(@datasource)
        allow(agent_factory).to receive(:send_schema).and_return(nil)
        agent_factory.build

        allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/users').and_return(
          instance_double(Faraday::Response,
                          status: 200,
                          body: [
                            {
                              'id' => 1,
                              'firstName' => 'John',
                              'lastName' => 'Doe',
                              'fullName' => 'John Doe',
                              'email' => 'john.doe@domain.com',
                              'tags' => [],
                              'roleId' => user_role_id,
                              'permissionLevel' => 'admin'
                            },
                            {
                              'id' => 3,
                              'firstName' => 'Admin',
                              'lastName' => 'test',
                              'fullName' => 'Admin test',
                              'email' => 'admin@forestadmin.com',
                              'tags' => [],
                              'roleId' => 13,
                              'permissionLevel' => 'admin'
                            }
                          ].to_json)
        )

        allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/environment').and_return(
          instance_double(Faraday::Response,
                          status: 200,
                          body: {
                            'collections' => {
                              'Book' => {
                                'collection' => {
                                  'browseEnabled' => {
                                    'roles' => [
                                      13,
                                      role_id
                                    ]
                                  },
                                  'readEnabled' => {
                                    'roles' => [
                                      13,
                                      role_id
                                    ]
                                  },
                                  'editEnabled' => {
                                    'roles' => [
                                      13,
                                      role_id
                                    ]
                                  },
                                  'addEnabled' => {
                                    'roles' => [
                                      13,
                                      role_id
                                    ]
                                  },
                                  'deleteEnabled' => {
                                    'roles' => [
                                      13,
                                      role_id
                                    ]
                                  },
                                  'exportEnabled' => {
                                    'roles' => [
                                      13,
                                      role_id
                                    ]
                                  }
                                },
                                'actions' => {
                                  'Mark as live' => {
                                    'triggerEnabled' => {
                                      'roles' => [
                                        13,
                                        role_id
                                      ]
                                    },
                                    'triggerConditions' => [
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
                                        'roleId' => 15
                                      }
                                    ],
                                    'approvalRequired' => {
                                      'roles' => []
                                    },
                                    'approvalRequiredConditions' => [],
                                    'userApprovalEnabled' => {
                                      'roles' => [
                                        13,
                                        role_id
                                      ]
                                    },
                                    'userApprovalConditions' => [],
                                    'selfApprovalEnabled' => {
                                      'roles' => [
                                        13,
                                        role_id
                                      ]
                                    }
                                  }
                                }
                              }
                            }
                          }.to_json)
        )

        @permissions = described_class.new(QueryStringParser.parse_caller(args))
        allow(@permissions).to receive(:forest_api).and_return(forest_api_requester)

        # clear permissions cache
        described_class.invalidate_cache
      end

      context 'when invalidate_cache is called' do
        it 'invalidates the cache' do
          @permissions.cache.get_or_set('foo') do
            'bar'
          end

          described_class.invalidate_cache('foo')

          expect(@permissions.cache.get('foo')).to be_nil
        end
      end

      context 'when the users list may be stale' do
        let(:john) do
          { 'id' => 1, 'firstName' => 'John', 'lastName' => 'Doe', 'fullName' => 'John Doe',
            'email' => 'john.doe@domain.com', 'tags' => [], 'roleId' => 1, 'permissionLevel' => 'user' }
        end
        let(:admin) do
          { 'id' => 3, 'firstName' => 'Admin', 'lastName' => 'test', 'fullName' => 'Admin test',
            'email' => 'admin@forestadmin.com', 'tags' => [], 'roleId' => 13, 'permissionLevel' => 'admin' }
        end

        def users_response(*users)
          instance_double(Faraday::Response, status: 200, body: users.to_json)
        end

        def stub_users(*responses)
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/users').and_return(*responses)
        end

        it 'reloads the users once when the id is unknown' do
          stub_users(users_response(admin), users_response(admin, john))

          expect(@permissions.get_user_data(1)).to include(id: 1, roleId: 1)
          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/users').twice
        end

        it 'does not reload the users when the id is known' do
          stub_users(users_response(admin, john))

          expect(@permissions.get_user_data(1)).to include(id: 1, roleId: 1)
          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/users').once
        end

        it 'reloads the users at most once per interval for an id that stays unknown' do
          stub_users(users_response(admin))

          2.times { expect(@permissions.get_user_data(42)).to be_nil }

          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/users').twice
        end

        it 'reloads the users again once the interval has elapsed' do
          stub_users(users_response(admin))
          allow(Process).to receive(:clock_gettime).and_call_original
          allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(
            1_000.0,
            1_000.0 + described_class::USERS_RELOAD_INTERVAL_IN_SECONDS + 1
          )

          2.times { @permissions.get_user_data(42) }

          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/users').exactly(3).times
        end

        it 'reloads the users on a denial so a role granted since the last load applies' do
          stub_users(users_response(john.merge('roleId' => 99)), users_response(john))

          expect(@permissions.can?(:browse, @datasource.collections['Book'])).to be true
          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/users').twice
        end

        it 'denies without reloading the users when a reload already ran within the interval' do
          stub_users(users_response(john.merge('roleId' => 99)), users_response(john))
          described_class.users_reload_allowed?

          expect do
            @permissions.can?(:browse, @datasource.collections['Book'])
          end.to raise_error(ForbiddenError)
          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/users').once
        end
      end

      context 'when can? is called' do
        it 'returns true when user is allowed' do
          expect(@permissions.can?(:browse, @datasource.collections['Book'])).to be true
        end

        it 'calls get_collections_permissions_data get_user_data & fetch to check if permissions has changed' do
          allow(@permissions).to receive(:get_user_data).and_return(
            {
              id: 1,
              firstName: 'John',
              lastName: 'Doe',
              fullName: 'John Doe',
              email: 'john.doe@domain.com',
              tags: [],
              roleId: 1,
              permissionLevel: 'admin'
            }
          )
          allow(@permissions).to receive(:fetch).and_return(
            {
              collections: {
                Book: {
                  collection: {
                    browseEnabled: {
                      roles: [1000]
                    },
                    readEnabled: {
                      oles: [1000]
                    },
                    editEnabled: {
                      roles: [1000]
                    },
                    addEnabled: {
                      roles: [1000]
                    },
                    deleteEnabled: {
                      roles: [1000]
                    },
                    exportEnabled: {
                      roles: [1000]
                    }
                  },
                  actions: []
                }
              }
            },
            {
              collections: {
                Book: {
                  collection: {
                    browseEnabled: {
                      roles: [1]
                    },
                    readEnabled: {
                      roles: [1]
                    },
                    editEnabled: {
                      roles: [1]
                    },
                    addEnabled: {
                      roles: [1]
                    },
                    deleteEnabled: {
                      roles: [1]
                    },
                    exportEnabled: {
                      roles: [1]
                    }
                  },
                  actions: []
                }
              }
            }
          )

          expect(@permissions.can?(:browse, @datasource.collections['Book'])).to be true
        end

        it "throws HttpException when user doesn't have the right access" do
          allow(@permissions).to receive(:get_user_data).and_return(
            {
              id: 1,
              firstName: 'John',
              lastName: 'Doe',
              fullName: 'John Doe',
              email: 'john.doe@domain.com',
              tags: [],
              roleId: 1,
              permissionLevel: 'admin'
            }
          )
          allow(@permissions).to receive(:fetch).and_return(
            {
              collections: {
                Book: {
                  collection: {
                    browseEnabled: {
                      roles: [1000]
                    },
                    readEnabled: {
                      roles: [1000]
                    },
                    editEnabled: {
                      roles: [1000]
                    },
                    addEnabled: {
                      roles: [1000]
                    },
                    deleteEnabled: {
                      roles: [1000]
                    },
                    exportEnabled: {
                      roles: [1000]
                    }
                  },
                  actions: []
                }
              }
            },
            {
              collections: {
                Book: {
                  collection: {
                    browseEnabled: {
                      roles: [1000]
                    },
                    readEnabled: {
                      roles: [1000]
                    },
                    editEnabled: {
                      roles: [1000]
                    },
                    addEnabled: {
                      roles: [1000]
                    },
                    deleteEnabled: {
                      roles: [1000]
                    },
                    exportEnabled: {
                      roles: [1000]
                    }
                  },
                  actions: []
                }
              }
            }
          )

          expect do
            @permissions.can?(:browse,
                              @datasource.collections['Book'])
          end.to raise_error(ForbiddenError, "You don't have permission to browse this collection.")
        end

        context 'when collection removed after first check (CRITICAL BUG FIX)' do
          it 'does not crash and raises ForbiddenError' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1
              }
            )

            # First fetch returns Book collection (user not allowed)
            # Second fetch (refetch) returns without Book collection
            allow(@permissions).to receive(:fetch).and_return(
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1000] },
                      readEnabled: { roles: [1000] },
                      editEnabled: { roles: [1000] },
                      addEnabled: { roles: [1000] },
                      deleteEnabled: { roles: [1000] },
                      exportEnabled: { roles: [1000] }
                    },
                    actions: []
                  }
                }
              },
              {
                collections: {} # Book collection removed!
              }
            )

            expect do
              @permissions.can?(:browse, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError, "You don't have permission to browse this collection.")
          end

          it 'logs debug message about missing collection after refetch' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1
              }
            )

            allow(@permissions).to receive(:fetch).and_return(
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1000] },
                      readEnabled: { roles: [1000] },
                      editEnabled: { roles: [1000] },
                      addEnabled: { roles: [1000] },
                      deleteEnabled: { roles: [1000] },
                      exportEnabled: { roles: [1000] }
                    },
                    actions: []
                  }
                }
              },
              {
                collections: {}
              }
            )

            # Allow any log calls but verify our specific one happens
            allow(ForestAdminAgent::Facades::Container.logger).to receive(:log).and_call_original

            expect do
              @permissions.can?(:browse, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError)

            expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log)
              .with('Warn', /Collection 'Book' not found/).at_least(:once)
          end
        end

        context 'when action removed after first check' do
          it 'does not crash and raises ForbiddenError' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1
              }
            )

            # First fetch has edit action (user not allowed)
            # Second fetch doesn't have edit action
            allow(@permissions).to receive(:fetch).and_return(
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1] },
                      readEnabled: { roles: [1] },
                      editEnabled: { roles: [1000] },
                      addEnabled: { roles: [1] },
                      deleteEnabled: { roles: [1] },
                      exportEnabled: { roles: [1] }
                    },
                    actions: []
                  }
                }
              },
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1] },
                      readEnabled: { roles: [1] },
                      addEnabled: { roles: [1] },
                      deleteEnabled: { roles: [1] },
                      exportEnabled: { roles: [1] }
                      # editEnabled removed!
                    },
                    actions: []
                  }
                }
              }
            )

            expect do
              @permissions.can?(:edit, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError, "You don't have permission to edit this collection.")
          end

          it 'logs debug message about missing action after refetch' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1
              }
            )

            allow(@permissions).to receive(:fetch).and_return(
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1] },
                      readEnabled: { roles: [1] },
                      editEnabled: { roles: [1000] },
                      addEnabled: { roles: [1] },
                      deleteEnabled: { roles: [1] },
                      exportEnabled: { roles: [1] }
                    },
                    actions: []
                  }
                }
              },
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1] },
                      readEnabled: { roles: [1] },
                      addEnabled: { roles: [1] },
                      deleteEnabled: { roles: [1] },
                      exportEnabled: { roles: [1] }
                    },
                    actions: []
                  }
                }
              }
            )

            # Allow any log calls but verify our specific one happens
            allow(ForestAdminAgent::Facades::Container.logger).to receive(:log).and_call_original

            expect do
              @permissions.can?(:edit, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError)

            expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log)
              .with('Warn', /Action 'edit' not found/).at_least(:once)
          end
        end

        context 'when refetch grants permission (happy path)' do
          it 'returns true after refetch' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1
              }
            )

            # First fetch: user not allowed
            # Second fetch: user now allowed
            allow(@permissions).to receive(:fetch).and_return(
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1000] },
                      readEnabled: { roles: [1000] },
                      editEnabled: { roles: [1000] },
                      addEnabled: { roles: [1000] },
                      deleteEnabled: { roles: [1000] },
                      exportEnabled: { roles: [1000] }
                    },
                    actions: []
                  }
                }
              },
              {
                collections: {
                  Book: {
                    collection: {
                      browseEnabled: { roles: [1] }, # User now allowed!
                      readEnabled: { roles: [1] },
                      editEnabled: { roles: [1] },
                      addEnabled: { roles: [1] },
                      deleteEnabled: { roles: [1] },
                      exportEnabled: { roles: [1] }
                    },
                    actions: []
                  }
                }
              }
            )

            expect(@permissions.can?(:browse, @datasource.collections['Book'])).to be true
          end
        end

        context 'when user_data is nil or incomplete' do
          it 'raises ForbiddenError when user_data is nil' do
            allow(@permissions).to receive_messages(get_user_data: nil, fetch: {
                                                      collections: {
                                                        Book: {
                                                          collection: {
                                                            browseEnabled: { roles: [1] },
                                                            readEnabled: { roles: [1] },
                                                            editEnabled: { roles: [1] },
                                                            addEnabled: { roles: [1] },
                                                            deleteEnabled: { roles: [1] },
                                                            exportEnabled: { roles: [1] }
                                                          },
                                                          actions: []
                                                        }
                                                      }
                                                    })

            expect do
              @permissions.can?(:browse, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError)
          end

          it 'raises ForbiddenError when roleId is missing' do
            allow(@permissions).to receive_messages(get_user_data: { id: 1 }, fetch: {
                                                      collections: {
                                                        Book: {
                                                          collection: {
                                                            browseEnabled: { roles: [1] },
                                                            readEnabled: { roles: [1] },
                                                            editEnabled: { roles: [1] },
                                                            addEnabled: { roles: [1] },
                                                            deleteEnabled: { roles: [1] },
                                                            exportEnabled: { roles: [1] }
                                                          },
                                                          actions: []
                                                        }
                                                      }
                                                    })

            expect do
              @permissions.can?(:browse, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError)
          end
        end

        context 'when roles array is nil' do
          it 'raises ForbiddenError without crashing' do
            allow(@permissions).to receive_messages(get_user_data: { id: 1, roleId: 1 }, fetch: {
                                                      collections: {
                                                        Book: {
                                                          collection: {
                                                            browseEnabled: { roles: nil }, # roles is nil, not the parent
                                                            readEnabled: { roles: [1] },
                                                            editEnabled: { roles: [1] },
                                                            addEnabled: { roles: [1] },
                                                            deleteEnabled: { roles: [1] },
                                                            exportEnabled: { roles: [1] }
                                                          },
                                                          actions: []
                                                        }
                                                      }
                                                    })

            expect do
              @permissions.can?(:browse, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError)
          end
        end

        context 'when roles array is empty' do
          it 'denies access when roles array is empty' do
            allow(@permissions).to receive_messages(get_user_data: { id: 1, roleId: 1 }, fetch: {
                                                      collections: {
                                                        Book: {
                                                          collection: {
                                                            browseEnabled: { roles: [] }, # Empty array
                                                            readEnabled: { roles: [1] },
                                                            editEnabled: { roles: [1] },
                                                            addEnabled: { roles: [1] },
                                                            deleteEnabled: { roles: [1] },
                                                            exportEnabled: { roles: [1] }
                                                          },
                                                          actions: []
                                                        }
                                                      }
                                                    })

            expect do
              @permissions.can?(:browse, @datasource.collections['Book'])
            end.to raise_error(ForbiddenError, "You don't have permission to browse this collection.")
          end
        end
      end

      context 'when can_execute_query_segment? is called' do
        let(:query) { 'select id from books' }
        let(:connection_name) { 'default' }

        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => nil,
                    'segments' => [],
                    'liveQuerySegments' => [{ query: query, connectionName: connection_name }]
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            )
          )
        end

        it 'returns true when user is allowed' do
          expect(@permissions.can_execute_query_segment?(@datasource.collections['Book'], query, connection_name)).to be true
        end

        it 'calls get_segments to check if permissions has changed' do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => nil,
                    'segments' => [],
                    'liveQuerySegments' => [{ query: query, connectionName: connection_name }]
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            ),
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => nil,
                    'segments' => [],
                    'liveQuerySegments' => [{ query: query, connectionName: 'primary' }]
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            )
          )

          expect(@permissions.can_execute_query_segment?(@datasource.collections['Book'], query, 'primary')).to be true
        end

        it "raise error when user doesn't have the right access" do
          allow(@permissions).to receive(:get_user_data).and_return(
            {
              id: 1,
              roleId: 1,
              permissionLevel: 'user'
            }
          )

          expect do
            @permissions.can_execute_query_segment?(@datasource.collections['Book'], query, 'foo')
          end.to raise_error(ForbiddenError, "You don't have permission to use this query segment.")
        end

        context 'with elevated permissions' do
          it 'returns true immediately for admin users without checking segments' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'admin'
              }
            )

            # Should not call get_collection_rendering_permissions
            allow(@permissions).to receive(:get_collection_rendering_permissions).and_call_original

            result = @permissions.can_execute_query_segment?(@datasource.collections['Book'], 'any query', 'any_connection')
            expect(result).to be true
            expect(@permissions).not_to have_received(:get_collection_rendering_permissions)
          end

          it 'returns true immediately for developer users without checking segments' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'developer'
              }
            )

            allow(@permissions).to receive(:get_collection_rendering_permissions).and_call_original

            result = @permissions.can_execute_query_segment?(@datasource.collections['Book'], 'any query', 'any_connection')
            expect(result).to be true
            expect(@permissions).not_to have_received(:get_collection_rendering_permissions)
          end

          it 'returns true immediately for editor users without checking segments' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'editor'
              }
            )

            allow(@permissions).to receive(:get_collection_rendering_permissions).and_call_original

            result = @permissions.can_execute_query_segment?(@datasource.collections['Book'], 'any query', 'any_connection')
            expect(result).to be true
            expect(@permissions).not_to have_received(:get_collection_rendering_permissions)
          end

          it 'logs debug message for admin users' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'admin'
              }
            )

            allow(ForestAdminAgent::Facades::Container.logger).to receive(:log).and_call_original

            @permissions.can_execute_query_segment?(@datasource.collections['Book'], query, connection_name)

            expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log)
              .with('Debug', /User 1 can retrieve SQL segment on rendering 114/).at_least(:once)
          end

          it 'checks permissions normally for non-elevated users' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'user'
              }
            )

            # Should call get_collection_rendering_permissions
            allow(@permissions).to receive(:get_collection_rendering_permissions).and_call_original

            @permissions.can_execute_query_segment?(@datasource.collections['Book'], query, connection_name)
            expect(@permissions).to have_received(:get_collection_rendering_permissions)
          end
        end

        context 'with permission refetch logic' do
          it 'refetches permissions when initially not allowed' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'user'
              }
            )

            # First call returns no matching segments
            # Second call (refetch) returns matching segments
            allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
              instance_double(
                Faraday::Response,
                status: 200,
                body: {
                  'collections' => {
                    'Book' => {
                      'scope' => nil,
                      'segments' => [],
                      'liveQuerySegments' => []
                    }
                  },
                  'stats' => [],
                  'team' => {}
                }.to_json
              ),
              instance_double(
                Faraday::Response,
                status: 200,
                body: {
                  'collections' => {
                    'Book' => {
                      'scope' => nil,
                      'segments' => [],
                      'liveQuerySegments' => [{ query: query, connectionName: connection_name }]
                    }
                  },
                  'stats' => [],
                  'team' => {}
                }.to_json
              )
            )

            result = @permissions.can_execute_query_segment?(@datasource.collections['Book'], query, connection_name)
            expect(result).to be true
          end

          it 'raises error when refetch still denies permission' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'user'
              }
            )

            # Both calls return no matching segments
            allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
              instance_double(
                Faraday::Response,
                status: 200,
                body: {
                  'collections' => {
                    'Book' => {
                      'scope' => nil,
                      'segments' => [],
                      'liveQuerySegments' => []
                    }
                  },
                  'stats' => [],
                  'team' => {}
                }.to_json
              ),
              instance_double(
                Faraday::Response,
                status: 200,
                body: {
                  'collections' => {
                    'Book' => {
                      'scope' => nil,
                      'segments' => [],
                      'liveQuerySegments' => []
                    }
                  },
                  'stats' => [],
                  'team' => {}
                }.to_json
              )
            )

            expect do
              @permissions.can_execute_query_segment?(@datasource.collections['Book'], query, connection_name)
            end.to raise_error(ForbiddenError, "You don't have permission to use this query segment.")
          end

          it 'calls get_collection_rendering_permissions twice when refetch is needed' do
            allow(@permissions).to receive(:get_user_data).and_return(
              {
                id: 1,
                roleId: 1,
                permissionLevel: 'user'
              }
            )

            allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
              instance_double(
                Faraday::Response,
                status: 200,
                body: {
                  'collections' => {
                    'Book' => {
                      'scope' => nil,
                      'segments' => [],
                      'liveQuerySegments' => []
                    }
                  },
                  'stats' => [],
                  'team' => {}
                }.to_json
              ),
              instance_double(
                Faraday::Response,
                status: 200,
                body: {
                  'collections' => {
                    'Book' => {
                      'scope' => nil,
                      'segments' => [],
                      'liveQuerySegments' => []
                    }
                  },
                  'stats' => [],
                  'team' => {}
                }.to_json
              )
            )

            # Spy on get_collection_rendering_permissions to verify it's called twice
            allow(@permissions).to receive(:get_collection_rendering_permissions).and_call_original

            expect do
              @permissions.can_execute_query_segment?(@datasource.collections['Book'], query, connection_name)
            end.to raise_error(ForbiddenError)

            expect(@permissions).to have_received(:get_collection_rendering_permissions)
              .with(@datasource.collections['Book'], force_fetch: false)
            expect(@permissions).to have_received(:get_collection_rendering_permissions)
              .with(@datasource.collections['Book'], force_fetch: true)
          end
        end
      end

      context 'when can_chart is called' do
        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(Faraday::Response,
                            status: 200,
                            body: {
                              'collections' => {
                                'Book' => {
                                  'scope' => nil,
                                  'segments' => [],
                                  'liveQuerySegments' => []
                                }
                              },
                              'stats' => [
                                {
                                  'type' => 'Pie',
                                  'filter' => nil,
                                  'aggregator' => 'Count',
                                  'groupByFieldName' => 'id',
                                  'aggregateFieldName' => nil,
                                  'sourceCollectionName' => 'Book'
                                },
                                {
                                  'type' => 'Value',
                                  'filter' => nil,
                                  'aggregator' => 'Count',
                                  'aggregateFieldName' => nil,
                                  'sourceCollectionName' => 'Book'
                                }
                              ],
                              'team' => {
                                'id' => 1,
                                'name' => 'Operations'
                              }
                            }.to_json)
          )
        end

        it 'returns true on allowed chart' do
          args[:params] = {
            aggregateFieldName: nil,
            aggregator: 'Count',
            contextVariables: '{}',
            filter: nil,
            sourceCollectionName: 'Book',
            type: 'Value'
          }

          expect(@permissions.can_chart?(args[:params])).to be true
        end

        it 'calls fetch twice and return true on allowed chart' do
          args[:params] = {
            aggregator: 'Count',
            groupByFieldName: 'id',
            sourceCollectionName: 'Book',
            type: 'Pie'
          }

          allow(@permissions).to receive(:fetch).and_return(
            {
              collections: {},
              stats: [],
              team: {}
            },
            {
              collections: {},
              stats: [
                {
                  type: 'Pie',
                  filter: nil,
                  aggregator: 'Count',
                  groupByFieldName: 'id',
                  aggregateFieldName: nil,
                  sourceCollectionName: 'Book'
                }
              ],
              team: {}
            }
          )

          expect(@permissions.can_chart?(args[:params])).to be true
        end

        it 'throws on forbidden chart' do
          args[:params] = {
            aggregator: 'Count',
            groupByFieldName: 'registrationNumber',
            sourceCollectionName: 'Car',
            type: 'Pie'
          }

          allow(@permissions).to receive(:fetch).and_return(
            {
              collections: {},
              stats: [],
              team: {}
            }
          )

          expect do
            @permissions.can_chart?(args[:params])
          end.to raise_error(ForbiddenError,
                             "You don't have permission to access this collection.")
        end
      end

      context 'when get_scope is called' do
        it 'returns nil when permission has no scopes' do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => nil,
                    'segments' => [],
                    'liveQuerySegments' => []
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            )
          )

          fake_collection = instance_double(Collection, name: 'FakeCollection')
          expect(@permissions.get_scope(fake_collection)).to be_nil
        end

        it 'works in simple case' do
          scope = {
            aggregator: 'and',
            conditions: [
              {
                field: 'id',
                operator: 'greater_than',
                value: '1'
              },
              {
                field: 'title',
                operator: 'present',
                value: nil
              }
            ]
          }
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => scope,
                    'segments' => [],
                    'liveQuerySegments' => []
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            )
          )

          expect(@permissions.get_scope(@datasource.collections['Book']).to_h)
            .to eq(ConditionTreeFactory.from_plain_object(scope).to_h)
        end

        it 'works with substitutions' do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => {
                      aggregator: 'and',
                      conditions: [
                        {
                          field: 'id',
                          operator: 'equal',
                          value: '{{currentUser.id}}'
                        }
                      ]
                    },
                    'segments' => [],
                    'liveQuerySegments' => []
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            )
          )

          expect(@permissions.get_scope(@datasource.collections['Book']).to_h)
            .to eq(ConditionTreeFactory.from_plain_object(
              {
                aggregator: 'and',
                conditions: [
                  {
                    field: 'id',
                    operator: 'equal',
                    value: 1
                  }
                ]
              }
            ).to_h)
        end

        it 'raises instead of silently resolving to nil when the caller\'s user data could not be resolved' do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114').and_return(
            instance_double(
              Faraday::Response,
              status: 200,
              body: {
                'collections' => {
                  'Book' => {
                    'scope' => {
                      aggregator: 'and',
                      conditions: [
                        {
                          field: 'id',
                          operator: 'equal',
                          value: '{{currentUser.id}}'
                        }
                      ]
                    },
                    'segments' => [],
                    'liveQuerySegments' => []
                  }
                },
                'stats' => [],
                'team' => {}
              }.to_json
            )
          )
          allow(@permissions).to receive(:get_user_data).and_return(nil)

          expect do
            @permissions.get_scope(@datasource.collections['Book'])
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            /Unable to resolve the caller's team or user data/
          )
        end
      end

      context 'when two renderings share the cache' do
        def rendering_response(scope_value)
          instance_double(
            Faraday::Response,
            status: 200,
            body: {
              'collections' => {
                'Book' => {
                  'scope' => { aggregator: 'and', conditions: [{ field: 'id', operator: 'equal', value: scope_value }] },
                  'segments' => [],
                  'liveQuerySegments' => []
                }
              },
              'stats' => [],
              'team' => {}
            }.to_json
          )
        end

        def scope_value_for(permissions)
          permissions.get_scope(@datasource.collections['Book']).to_h[:value]
        end

        let(:other_caller) do
          ForestAdminDatasourceToolkit::Components::Caller.new(
            id: 1, email: 'john.doe@domain.com', first_name: 'John', last_name: 'Doe', team: 'Sales',
            rendering_id: 115, tags: [], timezone: 'Europe/Paris', permission_level: 'admin', role: 'dev',
            request: { ip: '127.0.0.1' }, project: 'terminator', environment: 'Development'
          )
        end
        let(:other_permissions) { next_request(other_caller) }

        def next_request(caller)
          described_class.new(caller).tap do |permissions|
            allow(permissions).to receive(:forest_api).and_return(forest_api_requester)
          end
        end

        before do
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/114')
                                                      .and_return(rendering_response(114))
          allow(forest_api_requester).to receive(:get).with('/liana/v4/permissions/renderings/115')
                                                      .and_return(rendering_response(115))
        end

        it 'gives each rendering its own scope' do
          expect(scope_value_for(@permissions)).to eq 114

          expect(scope_value_for(other_permissions)).to eq 115
        end

        it 'invalidates one rendering without refetching the other' do
          scope_value_for(@permissions)
          scope_value_for(other_permissions)

          described_class.invalidate_rendering_cache(115)
          scope_value_for(next_request(@permissions.caller))
          scope_value_for(next_request(other_caller))

          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/renderings/114').once
          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/renderings/115').twice
        end

        it 'invalidates every rendering when no id is given' do
          scope_value_for(@permissions)
          scope_value_for(other_permissions)

          described_class.invalidate_rendering_cache
          scope_value_for(next_request(@permissions.caller))
          scope_value_for(next_request(other_caller))

          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/renderings/114').twice
          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/renderings/115').twice
        end

        it 'invalidates every rendering on a full cache clear' do
          scope_value_for(@permissions)

          described_class.invalidate_cache
          scope_value_for(next_request(@permissions.caller))

          expect(forest_api_requester).to have_received(:get).with('/liana/v4/permissions/renderings/114').twice
        end

        it 'does not raise when the rendering is not cached' do
          expect { described_class.invalidate_rendering_cache(999) }.not_to raise_error
        end

        it 'does not build the renderings cache for a request that never reads a rendering' do
          allow(ForestAdminAgent::Utils::SafeFileCache).to receive(:new).and_call_original

          described_class.new(QueryStringParser.parse_caller(args))

          expect(ForestAdminAgent::Utils::SafeFileCache).to have_received(:new).with('permissions', 'tmp/cache/forest_admin', 100)
          expect(ForestAdminAgent::Utils::SafeFileCache).not_to have_received(:new).with('permissions-renderings', any_args)
        end

        it 'builds the renderings cache once a rendering is read' do
          permissions = described_class.new(QueryStringParser.parse_caller(args))
          allow(permissions).to receive(:forest_api).and_return(forest_api_requester)
          allow(ForestAdminAgent::Utils::SafeFileCache).to receive(:new).and_call_original

          scope_value_for(permissions)

          expect(ForestAdminAgent::Utils::SafeFileCache).to have_received(:new).with('permissions-renderings', 'tmp/cache/forest_admin', 100).once
        end
      end

      context 'when can_smart_action? is called' do
        let(:book) { @datasource.collections['Book'] }
        let(:smart_action_args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              data: {
                attributes: {
                  'ids' => [1],
                  'collection_name' => 'Book',
                  'all_records' => false,
                  'all_records_ids_excluded' => [],
                  'smart_action_id' => 'make-photocopy',
                  'signed_approval_request' => nil
                },
                'type' => 'custom-action-requests'
              }
            }
          }
        end

        def declare_actions(collection, actions)
          allow(collection).to receive(:schema).and_return({ actions: actions })
        end

        def grant_trigger
          @permissions.cache.set('forest.has_permission', { enable: true })
          allow(@permissions).to receive_messages(
            get_user_data: { roleId: 15 },
            get_collections_permissions_data: { Book: { actions: { 'make-photocopy': { triggerEnabled: [15] } } } }
          )
        end

        it 'returns true when the permissions system is deactivate' do
          @permissions.cache.set('forest.has_permission', { enable: false })

          expect(
            @permissions.can_smart_action?(smart_action_args, book, Filter.new, action_name: 'make-photocopy')
          ).to be true
        end

        it 'throws when the action is unknown' do
          declare_actions(book, { 'make-photocopy' => instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction, scope: 'single') })
          grant_trigger

          expect do
            @permissions.can_smart_action?(smart_action_args, book, Filter.new, action_name: 'fake-smart-action')
          end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'The collection Book does not have this smart action')
        end

        it 'throws when the collection declares no action' do
          declare_actions(book, {})
          grant_trigger

          expect do
            @permissions.can_smart_action?(smart_action_args, book, Filter.new, action_name: 'make-photocopy')
          end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'The collection Book does not have this smart action')
        end

        it 'hands the collection schema action scope to the smart action checker' do
          declare_actions(book, { 'make-photocopy' => instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction, scope: 'global') })
          grant_trigger
          checker = instance_double(SmartActionChecker, can_execute?: true)
          allow(SmartActionChecker).to receive(:new).and_return(checker)

          expect(
            @permissions.can_smart_action?(smart_action_args, book, Filter.new, action_name: 'make-photocopy')
          ).to be true
          # The schema scope must reach the checker: without it a global action would be resolved.
          expect(SmartActionChecker).to have_received(:new).with(
            anything, book, hash_including(scope: 'global', triggerEnabled: [15]), anything, 15, anything
          )
        end

        it 'does not read the schema file' do
          declare_actions(book, { 'make-photocopy' => instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction, scope: 'single') })
          grant_trigger
          allow(SmartActionChecker).to receive(:new).and_return(instance_double(SmartActionChecker, can_execute?: true))
          allow(File).to receive(:read).and_call_original

          @permissions.can_smart_action?(smart_action_args, book, Filter.new, action_name: 'make-photocopy')

          expect(File).not_to have_received(:read).with(Facades::Container.config_from_cache[:schema_path])
        end
      end
    end
  end
end
