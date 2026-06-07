# MariaDB 10.7+ has a native `UUID` column type (formerly used by the email app's
# `uuid` column). Active Record's MySQL/trilogy adapter doesn't know this type,
# so column reflection leaves the column with no cast type, which breaks both
# `db:schema:dump` ("Unknown type 'uuid'") and any model that loads the table.
# Treat `uuid` columns as plain strings for reading, writing, and schema dumping.
require "active_record/connection_adapters/abstract_mysql_adapter"

module MariaDBUUIDType
  def lookup_cast_type(sql_type)
    return ActiveRecord::Type::String.new if sql_type.to_s.match?(/\Auuid\b/i)
    super
  end
end

ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter.prepend(MariaDBUUIDType)
