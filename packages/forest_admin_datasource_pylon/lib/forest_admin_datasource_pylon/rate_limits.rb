module ForestAdminDatasourcePylon
  # The per-endpoint budgets Pylon documents, in requests per minute, read off
  # the API reference (docs.usepylon.com/pylon-docs/developer/api/api-reference,
  # one page per resource — each endpoint states its own "Rate limit:" line).
  #
  # Pylon meters per endpoint, not per token, so every rule owns its own window:
  # two endpoints allowing 300 each are 600 requests, and pooling them would
  # throttle at half the budget the API grants.
  #
  # An endpoint absent from the table falls back to DEFAULT_LIMIT, the lowest
  # figure documented anywhere on the API. An undocumented quota is not an
  # absent one, and the generous guess is the one an operator discovers as a 429.
  class RateLimits
    DEFAULT_LIMIT = 30

    # Ids are escaped before being joined to a path, so a segment never carries
    # a slash and this matches exactly one of them.
    ID = '[^/]+'.freeze

    Rule = Struct.new(:name, :limit, keyword_init: true)

    # Every rule is anchored, so `/issues`, `/issues/{id}` and
    # `/issues/{id}/messages` are three distinct buckets rather than three
    # readings of the same prefix, and the order of this list carries no meaning.
    #
    # `name` is what the window is keyed on and what a log line shows, so it
    # spells the endpoint rather than its budget: two endpoints sharing a figure
    # must not share a window.
    RULES = [
      ['post /issues/search',           :post,   %r{\A/issues/search\z},              120],
      ['post /accounts/search',         :post,   %r{\A/accounts/search\z},            120],
      ['post /contacts/search',         :post,   %r{\A/contacts/search\z},            120],
      ['get /issues/:id/messages',      :get,    %r{\A/issues/#{ID}/messages\z},      120],
      ['get /issues',                   :get,    %r{\A/issues\z},                      30],
      ['post /issues',                  :post,   %r{\A/issues\z},                      30],
      ['get /issues/:id',               :get,    %r{\A/issues/#{ID}\z},               300],
      ['patch /issues/:id',             :patch,  %r{\A/issues/#{ID}\z},               120],
      ['get /accounts',                 :get,    %r{\A/accounts\z},                   300],
      ['get /accounts/:id',             :get,    %r{\A/accounts/#{ID}\z},             300],
      ['get /contacts',                 :get,    %r{\A/contacts\z},                   300],
      ['get /contacts/:id',             :get,    %r{\A/contacts/#{ID}\z},             300],
      ['get /users',                    :get,    %r{\A/users\z},                      300],
      ['get /users/:id',                :get,    %r{\A/users/#{ID}\z},                300],
      ['get /teams',                    :get,    %r{\A/teams\z},                      300],
      ['get /teams/:id',                :get,    %r{\A/teams/#{ID}\z},                300],
      ['get /custom-fields',            :get,    %r{\A/custom-fields\z},              300]
    ].map { |name, verb, pattern, limit| [verb, pattern, Rule.new(name: name, limit: limit)] }.freeze

    class << self
      def for(method, path)
        verb = method.to_s.downcase.to_sym
        normalized = normalize(path)

        found = RULES.find { |rule_verb, pattern, _rule| rule_verb == verb && pattern.match?(normalized) }
        found ? found[2] : fallback(verb, normalized)
      end

      private

      # Faraday hands back the path of the resolved URL, which carries the
      # leading slash the rules are written against and, on a base url mounted
      # under a subpath, whatever precedes it.
      def normalize(path)
        stripped = path.to_s.chomp('/')
        stripped.start_with?('/') ? stripped : "/#{stripped}"
      end

      # An unlisted endpoint is bucketed by its first segment rather than by its
      # full path: keying on the path would open a window per record id, so a
      # fan-out over a hundred records would meter as a hundred endpoints each
      # one request in.
      def fallback(verb, path)
        segment = path.split('/').reject(&:empty?).first
        Rule.new(name: "#{verb} /#{segment} (undocumented)", limit: DEFAULT_LIMIT)
      end
    end
  end
end
