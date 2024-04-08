module ColumnSchemaFactory
  include ForestAdminDatasourceToolkit::Schema
  include ForestAdminDatasourceToolkit::Validations

  def column_build(args = {})
    ColumnSchema.new(column_type: 'String', **args)
  end

  def numeric_primary_key_build(args = {})
    ColumnSchema.new(
      is_primary_key: true,
      column_type: 'Number',
      filter_operators: Rules.get_allowed_operators_for_column_type('Number'),
      **args
    )
  end

  def uuid_primary_key_build(args = {})
    ColumnSchema.new(
      is_primary_key: true,
      column_type: 'Uuid',
      filter_operators: Rules.get_allowed_operators_for_column_type('Uuid'),
      **args
    )
  end

  def many_to_many_build(args = {})
    Relations::ManyToManySchema.new(origin_key_target: 'id', foreign_key_target: 'id', **args)
  end

  def many_to_one_build(args = {})
    Relations::ManyToOneSchema.new(foreign_key_target: 'id', **args)
  end

  def one_to_one_build(args = {})
    Relations::OneToOneSchema.new(origin_key_target: 'id', **args)
  end

  def one_to_many_build(args = {})
    Relations::OneToManySchema.new(origin_key_target: 'id', **args)
  end
end
