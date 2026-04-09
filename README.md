# Flehmen

<img width="410" height="410" alt="flehmen-response-cat" src="https://github.com/ryosk7/flehmen/blob/master/logo/flehmen-response-cat.png?raw=true" />

A Ruby gem that exposes Rails ActiveRecord models to Claude Desktop via the Model Context Protocol (MCP). It auto-discovers models, provides read-only query tools, and filters sensitive fields.

## Installation

Add to your Gemfile:

```ruby
gem "flehmen"
```

```bash
bundle install
```

## Setup

### Rails initializer

Create `config/initializers/flehmen.rb`:

```ruby
Flehmen.configure do |config|
  config.exclude_models = []
  config.sensitive_fields = %i[
    password_digest encrypted_password token secret
    api_key api_secret access_token refresh_token
    otp_secret reset_password_token encrypted_phone
  ]
  config.max_results = 100
end

Flehmen.mount_in_rails(Rails.application, path_prefix: "/mcp", localhost_only: false)
```

### Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "flehmen": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:3000/mcp/sse", "--allow-http"]
    }
  }
}
```

> **Note:** The URL must end with `/mcp/sse`. The underlying `fast_mcp` gem uses SSE transport, so `/mcp` alone will return 404.

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `models` | `:all` or `Array` | `:all` | Models to expose. `:all` auto-discovers all `ApplicationRecord` descendants |
| `exclude_models` | `Array` | `[]` | Model classes or strings to exclude |
| `sensitive_fields` | `Array<Symbol>` | See below | Fields masked with `[FILTERED]` across all models |
| `model_sensitive_fields` | `Hash` | `{}` | Per-model sensitive fields |
| `max_results` | `Integer` | `100` | Maximum records returned by any query |
| `read_only_connection` | `Boolean` | `true` | Wraps all queries in `while_preventing_writes` to block accidental writes at the Rails level |

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
Flehmen.configure do |config|
  config.exclude_models = [AdminUser, "InternalLog"]
  config.sensitive_fields += [:ssn, :credit_card_number]
  config.model_sensitive_fields = {
    "User" => [:phone_number, :address]
  }
  config.max_results = 50
end
```

## Tools

### flehmen_list_models

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

### flehmen_describe_model

Returns schema details (columns, associations, enums) for a model.

```
Arguments:
  model_name (required) - e.g. "User"
```

### flehmen_find_record

Finds a single record by primary key.

```
Arguments:
  model_name (required)
  id         (required)
```

### flehmen_search_records

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

### flehmen_count_records

Counts records matching conditions.

```
Arguments:
  model_name (required)
  conditions (optional) - Same format as search_records
```

### flehmen_show_associations

Fetches associated records for a given record.

```
Arguments:
  model_name       (required)
  id               (required)
  association_name (required) - e.g. "posts", "company"
  limit            (optional) - For has_many associations
  offset           (optional)
```


## Resources

### flehmen://schema/overview

Returns a JSON overview of all models including columns, associations, and enums.

## Architecture

```
Flehmen.mount_in_rails(app)
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
- `activerecord` ~> 7.0
- `activesupport` ~> 7.0
- `railties` ~> 7.0

## License

MIT
