# Synapse

A Ruby gem that exposes Rails ActiveRecord models to Claude Desktop via the Model Context Protocol (MCP). It auto-discovers models, provides read-only query tools, and filters sensitive fields.

## Installation

Add to your Gemfile:

```ruby
gem "synapse", github: "ryosk7/synapse"
```

```bash
bundle install
```

## Setup

### Rails initializer

Create `config/initializers/synapse.rb`:

```ruby
Synapse.configure do |config|
  config.exclude_models = []
  config.sensitive_fields = %i[
    password_digest encrypted_password token secret
    api_key api_secret access_token refresh_token
    otp_secret reset_password_token encrypted_phone
  ]
  config.max_results = 100
  config.enable_raw_sql = false
end

Synapse.mount_in_rails(Rails.application, path_prefix: "/mcp", localhost_only: false)
```

### Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "synapse": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:3000/mcp/sse", "--allow-http"]
    }
  }
}
```

> **Note:** The URL must end with `/mcp/sse`. The underlying `fast_mcp` gem uses SSE transport, so `/mcp` alone will return 404.

### Claude Code

Add to `.mcp.json`:

```json
{
  "mcpServers": {
    "synapse": {
      "type": "sse",
      "url": "http://localhost:3000/mcp/sse"
    }
  }
}
```

Replace `localhost:3000` with your service URL in production.

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `models` | `:all` or `Array` | `:all` | Models to expose. `:all` auto-discovers all `ApplicationRecord` descendants |
| `exclude_models` | `Array` | `[]` | Model classes or strings to exclude |
| `sensitive_fields` | `Array<Symbol>` | See below | Fields masked with `[FILTERED]` across all models |
| `model_sensitive_fields` | `Hash` | `{}` | Per-model sensitive fields |
| `max_results` | `Integer` | `100` | Maximum records returned by any query |
| `enable_raw_sql` | `Boolean` | `false` | Enables the `execute_query` tool when `true` |

### Default sensitive fields

```ruby
%i[
  password_digest encrypted_password token secret
  api_key api_secret access_token refresh_token
  otp_secret reset_password_token confirmation_token
  unlock_token remember_token authentication_token
]
```

### Example

```ruby
Synapse.configure do |config|
  config.exclude_models = [AdminUser, "InternalLog"]
  config.sensitive_fields += [:ssn, :credit_card_number]
  config.model_sensitive_fields = {
    "User" => [:phone_number, :address]
  }
  config.max_results = 50
  config.enable_raw_sql = true
end
```

## Tools

### synapse_list_models

Lists all discovered models.

```
Arguments: none
```

Returns:
```json
[
  {
    "name": "User",
    "table_name": "users",
    "column_count": 15,
    "association_count": 8,
    "enum_count": 2
  }
]
```

### synapse_describe_model

Returns schema details (columns, associations, enums) for a model.

```
Arguments:
  model_name (required) - e.g. "User"
```

### synapse_find_record

Finds a single record by primary key.

```
Arguments:
  model_name (required)
  id         (required)
```

### synapse_search_records

Searches records with structured conditions.

```
Arguments:
  model_name (required)
  conditions (optional) - JSON string
  order_by   (optional) - Column name to sort by
  order_dir  (optional) - "asc" or "desc" (default: "asc")
  limit      (optional)
  offset     (optional)
```

Conditions format:
```json
[
  {"field": "status", "operator": "eq", "value": "active"},
  {"field": "created_at", "operator": "gte", "value": "2025-01-01"}
]
```

Supported operators: `eq`, `not_eq`, `gt`, `gte`, `lt`, `lte`, `like`, `not_like`, `in`, `not_in`, `null`, `not_null`

### synapse_count_records

Counts records matching conditions.

```
Arguments:
  model_name (required)
  conditions (optional) - Same format as search_records
```

### synapse_show_associations

Fetches associated records for a given record.

```
Arguments:
  model_name       (required)
  id               (required)
  association_name (required) - e.g. "posts", "company"
  limit            (optional) - For has_many associations
  offset           (optional)
```

### synapse_execute_query

Executes raw SQL (only available when `enable_raw_sql: true`).

```
Arguments:
  sql   (required) - SELECT statement
  limit (optional)
```

Security constraints:
- Only `SELECT` statements are allowed
- `INSERT`, `UPDATE`, `DELETE`, `DROP`, etc. are blocked
- SQL comments are stripped
- `LIMIT` is auto-appended if missing

## Resources

### synapse://schema/overview

Returns a JSON overview of all models including columns, associations, and enums.

## Architecture

```
Synapse.mount_in_rails(app)
  └── FastMcp.mount_in_rails (Rack middleware)
        ├── GET  /mcp/sse       → SSE connection (keep-alive)
        └── POST /mcp/messages  → JSON-RPC message handling
```

- **ModelRegistry** - Auto-discovers models on first access (lazy loading)
- **FieldFilter** - Masks sensitive fields with `[FILTERED]`
- **QueryBuilder** - Builds Arel-based queries from structured conditions (SQL injection safe)
- **Serializer** - Converts records to filtered hashes

## Dependencies

- Ruby >= 3.1.0
- `fast-mcp` ~> 1.5
- `activerecord` >= 7.0
- `activesupport` >= 7.0
- `railties` >= 7.0

## License

MIT
