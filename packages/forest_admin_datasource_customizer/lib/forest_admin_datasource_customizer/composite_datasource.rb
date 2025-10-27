module ForestAdminDatasourceCustomizer
  class CompositeDatasource
    def initialize
      @datasources = []
    end

    def live_query_connections
      @datasources.each_with_object({}) do |ds, acc|
        acc.merge!(ds.live_query_connections || {})
      end
    end

    def schema
      { charts: @datasources.flat_map { |ds| ds.schema[:charts] } }
    end

    def collections
      @datasources.reduce({}) { |acc, ds| acc.merge(ds.collections) }
    end

    def get_collection(name)
      @datasources.each do |ds|
        return ds.get_collection(name)
      rescue StandardError
        # ignore and continue
      end

      raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
            "Collection '#{name}' not found. List of available collections: #{collections.keys.sort.join(", ")}"
    end

    def render_chart(caller_obj, name)
      @datasources.each do |ds|
        return ds.render_chart(caller_obj, name) if ds.schema[:charts].include?(name)
      end

      raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
            "Chart '#{name}' is not defined in the dataSource."
    end

    def execute_native_query(connection_name, query, context_variables = {})
      unless live_query_connections.key?(connection_name)
        raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "Native query connection '#{name}' is unknown."
      end

      ds = @datasources.find do |d|
        (d.live_query_connections || {}).key?(connection_name)
      end

      ds.execute_native_query(connection_name, query, context_variables)
    end

    def add_data_source(datasource)
      existing_names = collections.map { |c| c.respond_to?(:name) ? c.name : c.to_s }
      datasource.collections.each do |c|
        new_name = c.respond_to?(:name) ? c.name : c.to_s
        raise ArgumentError, "Collection '#{new_name}' already exists" if existing_names.include?(new_name)
      end

      existing_charts = schema[:charts]
      (datasource.schema[:charts] || []).each do |chart|
        raise ArgumentError, "Chart '#{chart}' is already defined in datasource." if existing_charts.include?(chart)
      end

      existing_conns = live_query_connections
      (datasource.live_query_connections || {}).each_key do |conn_name|
        if existing_conns.key?(conn_name)
          raise ArgumentError, "Native Query connection '#{conn_name}' is already defined"
        end
      end

      @datasources << datasource
      nil
    end
  end
end
