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
          expect do
            @permissions.can?(@permissions.can_execute_query_segment?(@datasource.collections['Book'], query, 'foo'))
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
                    value: '1'
                  }
                ]
              }
            ).to_h)
        end
      end

      context 'when can_smart_action? is called' do
        it 'returns true when the permissions system is deactivate' do
          args[:headers]['REQUEST_PATH'] = '/forest/_actions/Book/0/make-photocopy'
          args[:headers]['REQUEST_METHOD'] = 'POST'
          args[:params] = {
            data: {
              attributes: {
                'values' => [],
                'ids' => [1],
                'collection_name' => 'Book',
                'parent_collection_name' => nil,
                'parent_collection_id' => nil,
                'parent_association_name' => nil,
                'all_records' => false,
                'all_records_subset_query' => {
                  'fields[Book]' => 'id,title',
                  'page[number]' => 1,
                  'page[size]' => 15,
                  'sort' => '-id',
                  'timezone' => 'Europe/Paris'
                },
                'all_records_ids_excluded' => [],
                'smart_action_id' => 'make-photocopy',
                'signed_approval_request' => nil
              },
              'type' => 'custom-action-requests'
            }
          }

          @permissions.cache.set('forest.has_permission', { enable: false })

          expect(@permissions.can_smart_action?(args, @datasource.collections['Book'], Filter.new)).to be true
        end

        it 'throws when the action is unknown' do
          args[:headers]['REQUEST_PATH'] = '/forest/_actions/Book/0/fake-smart-action'
          args[:headers]['REQUEST_METHOD'] = 'POST'
          args[:params] = {
            data: {
              attributes: {
                'values' => [],
                'ids' => [1],
                'collection_name' => 'FakeCollection',
                'parent_collection_name' => nil,
                'parent_collection_id' => nil,
                'parent_association_name' => nil,
                'all_records' => false,
                'all_records_subset_query' => {
                  'fields[Book]' => 'id,title',
                  'page[number]' => 1,
                  'page[size]' => 15,
                  'sort' => '-id',
                  'timezone' => 'Europe/Paris'
                },
                'all_records_ids_excluded' => [],
                'smart_action_id' => 'FakeCollection-fake-smart-action',
                'signed_approval_request' => nil
              },
              'type' => 'custom-action-requests'
            }
          }

          expect do
            @permissions.can_smart_action?(args, @datasource.collections['Book'], Filter.new)
          end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'The collection Book does not have this smart action')
        end

        it "throws when the forest schema doesn't have any actions" do
          args[:headers]['REQUEST_PATH'] = '/forest/_actions/FakeCollection/0/fake-smart-action'
          args[:headers]['REQUEST_METHOD'] = 'POST'
          args[:params] = {
            data: {
              attributes: {
                'values' => [],
                'ids' => [1],
                'collection_name' => 'FakeCollection',
                'parent_collection_name' => nil,
                'parent_collection_id' => nil,
                'parent_association_name' => nil,
                'all_records' => false,
                'all_records_subset_query' => {
                  'fields[Book]' => 'id,title',
                  'page[number]' => 1,
                  'page[size]' => 15,
                  'sort' => '-id',
                  'timezone' => 'Europe/Paris'
                },
                'all_records_ids_excluded' => [],
                'smart_action_id' => 'FakeCollection-fake-smart-action',
                'signed_approval_request' => nil
              },
              'type' => 'custom-action-requests'
            }
          }

          expect do
            @permissions.can_smart_action?(args, @datasource.collections['Book'], Filter.new)
          end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'The collection Book does not have this smart action')
        end
      end
    end
  end
end
