module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      # The allow-list of `POST /issues/search`, transcribed from the API
      # reference: a field absent from this table cannot be filtered at all, and
      # an operator absent from a field's map is rejected by Pylon.
      #
      # It is the single source of truth for filtering — `define_schema` derives
      # every column's `filter_operators` from it, so this collection declares no
      # filter the translator would then refuse; the absence family the agent
      # derives on top of it is the exception `Query::OperatorMaps::Table`
      # describes.
      module ApiFilters
        Maps = Query::OperatorMaps

        extend Maps::Table

        CUSTOM_FIELD_OPS = Maps::CUSTOM_FIELD_OPS

        # `param` carries the read-to-filter renames: an issue is read with
        # `type` / `resolution_time` / `latest_message_time` but filtered on
        # `issue_type` / `resolved_at` / `latest_message_activity_at`.
        API_FILTERS = {
          'state' => { ops: Maps::EQUALITY },
          'type' => { param: 'issue_type', ops: Maps::EQUALITY.merge(Maps::PRESENCE) },
          'account_id' => { ops: Maps::EQUALITY.merge(Maps::PRESENCE) },
          'requester_id' => { ops: Maps::EQUALITY.merge(Maps::PRESENCE) },
          'assignee_id' => { ops: Maps::EQUALITY.merge(Maps::PRESENCE) },
          'team_id' => { ops: Maps::EQUALITY },
          'title' => { ops: Maps::FULL_TEXT },
          'body_html' => { ops: Maps::FULL_TEXT },
          'tags' => { ops: Maps::MEMBERSHIP },
          'created_at' => { ops: Maps::TIME },
          'updated_at' => { ops: Maps::TIME },
          'resolution_time' => { param: 'resolved_at', ops: Maps::TIME },
          'latest_message_time' => { param: 'latest_message_activity_at', ops: Maps::TIME }
        }.freeze
      end
    end
  end
end
