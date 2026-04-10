# CLAUDE.md

Guidance for Claude Code (and other AI assistants) working in this repository.

## Project overview

**Flehmen** is a Ruby gem that exposes a host Rails application's ActiveRecord
models to Claude Desktop (or any MCP client) via the Model Context Protocol.
It auto-discovers models, exposes a fixed set of read-only query tools, and
filters sensitive fields before returning data.

- Gem name: `flehmen`
- Language: Ruby (`>= 3.1.0`)
- Core dependency: `fast-mcp ~> 1.5` (provides transport and `FastMcp::Tool` / `FastMcp::Resource` / `FastMcp.mount_in_rails`)
- Rails deps pinned to `~> 7.0` (`activerecord`, `activesupport`, `railties`)
- Version: see `lib/flehmen/version.rb`

This is a **library gem** — there is no application to run in this repo. It is
designed to be installed into a host Rails app, which provides the models and
database connection.

## Repository layout

```
bin/flehmen                              # STDIO entry point (loads host Rails app, starts server)
flehmen.gemspec                          # Gem metadata and dependencies
Gemfile                                  # Adds rspec + sqlite3 for dev/test
lib/flehmen.rb                           # Top-level module, public API (Flehmen.catloaf, Flehmen.configure, ...)
lib/flehmen/version.rb
lib/flehmen/configuration.rb             # Config struct + validate!
lib/flehmen/model_registry.rb            # Lazy ApplicationRecord discovery
lib/flehmen/field_filter.rb              # [FILTERED] masking (global + per-model)
lib/flehmen/query_builder.rb             # Arel-based condition building (SQL-injection safe)
lib/flehmen/serializer.rb                # Record -> filtered attributes hash
lib/flehmen/tools/base.rb                # FastMcp::Tool subclass: auth + read-only wrapper
lib/flehmen/tools/list_models_tool.rb        # flehmen_list_models
lib/flehmen/tools/describe_model_tool.rb     # flehmen_describe_model
lib/flehmen/tools/find_record_tool.rb        # flehmen_find_record
lib/flehmen/tools/search_records_tool.rb     # flehmen_search_records
lib/flehmen/tools/count_records_tool.rb      # flehmen_count_records
lib/flehmen/tools/show_associations_tool.rb  # flehmen_show_associations
lib/flehmen/resources/schema_overview_resource.rb   # flehmen://schema/overview
logo/                                    # Logo assets only
```

There is **no `spec/` directory** in the repo currently, even though `rspec`
and `sqlite3` are declared as dev dependencies in the `Gemfile`. If you add
tests, create `spec/` and the usual `spec_helper.rb` scaffolding; do not
assume existing fixtures.

## Runtime architecture

Two entry points:

1. **Rack middleware (primary)** — `Flehmen.catloaf(app, options)` in
   `lib/flehmen.rb:55`. Called from a Rails initializer. Delegates to
   `FastMcp.mount_in_rails`, which installs middleware at `path_prefix` (default
   `/mcp`). Exposes `GET /mcp/sse` (SSE keep-alive) and `POST /mcp/messages`
   (JSON-RPC). Note: the Claude Desktop config URL must end in `/mcp/sse`,
   not `/mcp`.

2. **STDIO transport** — `bin/flehmen`. Boots the host Rails app via
   `RAILS_APP_PATH` (or `Dir.pwd`), eager-loads, then calls
   `Flehmen.start_server!`. Used for local Claude Desktop integrations that
   spawn a subprocess. **STDIO skips authentication entirely** (it is
   inherently local) — see README "Authentication" note.

Tool pipeline for every request:

```
FastMcp transport
  → Tools::Base#call
      → ActiveRecord::Base.while_preventing_writes(config.read_only_connection) do
          execute(**args)   # defined in each tool subclass
        end
  → JSON response
```

`ModelRegistry` is **lazy**: `Flehmen.model_registry` memoizes the result of
`boot!`, which walks `ApplicationRecord.descendants` (falling back to
`ActiveRecord::Base`). Models without a table, abstract classes, excluded
classes, or anything that raises during introspection are silently skipped
(`model_registry.rb:22-31`). Call `Flehmen.reset_configuration!` in tests to
clear both the configuration and the cached registry.

## Key conventions

### Security / safety (very important)

This gem runs against real production databases, so conservatism is the rule:

- **All queries are read-only.** `Tools::Base#call` wraps every `execute` in
  `while_preventing_writes`. Do not bypass this. Even new tools must inherit
  from `Flehmen::Tools::Base` so the wrapper applies.
- **No raw SQL.** An earlier `ExecuteQueryTool` / `enable_raw_sql` option was
  removed deliberately (commit `c0ba040`). Do not reintroduce raw-SQL tools
  or string interpolation into queries. Use `QueryBuilder`, which is Arel-based
  and validates column names and operators against an allowlist
  (`query_builder.rb:5`, `query_builder.rb:33-36`).
- **Column + operator allowlisting.** `QueryBuilder#apply_condition` raises
  `ArgumentError` on unknown columns or operators. When adding features,
  preserve this validation — never trust field names coming from the LLM.
- **LIKE is sanitized.** `sanitize_like` escapes `\`, `%`, and `_` so users
  can't inject wildcards through `like` / `not_like` operators.
- **Input caps.** `search_records_tool` and `show_associations_tool` enforce
  `limit` ≤ 100 and `offset` ≤ 10_000 via dry-validation in the `arguments`
  block. `in` / `not_in` arrays are capped at `config.max_results`
  (`query_builder.rb:49-50`). Preserve these caps when editing.
- **Sensitive field masking.** `FieldFilter` replaces sensitive attribute
  values with `"[FILTERED]"`. It combines global `config.sensitive_fields`
  with per-model `config.model_sensitive_fields`. Always run record
  attributes through `Serializer` (which calls `FieldFilter`) before
  returning them — never serialize `record.attributes` directly.
- **Authentication modes are mutually exclusive.** `auth_token` (static
  Bearer) and `authenticate` (Proc callback) cannot both be set;
  `Configuration#validate!` raises `Flehmen::ConfigurationError` if they
  are. `validate!` is called from both `catloaf` and `start_server!`.

### Auth callback plumbing

- When `config.authenticate` is set, `Flehmen#setup_auth_filters`
  (`lib/flehmen.rb:78`) installs `server.filter_tools` / `server.filter_resources`
  hooks that call the Proc with a lowercased, hyphen-separated header hash
  (e.g. `'authorization'`, `'x-api-key'`) extracted from `request.env`.
- `Tools::Base` also re-runs the auth Proc inside its `authorize` block and
  stashes the return value in `@current_user`, exposed via `attr_reader
  :current_user` for use inside custom `execute` methods.
- The `next true if headers.nil? || headers.empty?` guard in
  `tools/base.rb:11` allows STDIO calls (which have no HTTP headers) to pass
  through without auth.

### Tool conventions

Every tool in `lib/flehmen/tools/` follows the same pattern:

```ruby
class SomeTool < Base
  tool_name "flehmen_some_thing"        # must start with "flehmen_"
  description "..."                      # shown to the LLM; be explicit about args
  arguments do
    required(:model_name).filled(:string).description("...")
    optional(:limit).filled(:integer).value(gteq?: 1, lteq?: 100).description("...")
  end
  annotations(read_only_hint: true, open_world_hint: false)

  def execute(model_name:, ...)
    info = Flehmen.model_registry.find_model(model_name)
    return JSON.generate({ error: "Model not found: #{model_name}" }) unless info
    # ... use QueryBuilder / Serializer ...
    JSON.generate(result)
  rescue JSON::ParserError
    JSON.generate({ error: "Invalid JSON in conditions parameter" })
  rescue ArgumentError => e
    JSON.generate({ error: e.message })
  end
end
```

Conventions to preserve when adding or editing tools:

- Tool names are prefixed `flehmen_` and registered in
  `Flehmen.register_tools` (`lib/flehmen.rb:107`). Registering a new tool
  requires adding it to both that method **and** the `require_relative` list
  at the top of `lib/flehmen.rb`.
- Annotate every tool with `read_only_hint: true, open_world_hint: false`.
  If you ever add a non-read-only tool, you must also rethink the
  `while_preventing_writes` wrapper in `Tools::Base`.
- **Error responses are JSON blobs**, not raised exceptions —
  `JSON.generate({ error: "..." })`. Catch `JSON::ParserError` and
  `ArgumentError` from `QueryBuilder` and translate them. Don't let
  exceptions escape `execute`.
- Resolve models via `Flehmen.model_registry.find_model(name)` which handles
  both `"User"` and `"user"` style inputs (via `classify`).
- Serialize records via `Flehmen::Serializer.new.serialize_record(s)` so
  sensitive fields are filtered consistently.

### Configuration

Defaults live in `Configuration#initialize` (`lib/flehmen/configuration.rb:16`).
The full option list is documented in `README.md`. When adding a new option,
add it to `attr_accessor`, set a default in `initialize`, update
`validate!` if it has compatibility constraints, and document it in
`README.md`'s configuration table.

## Development workflows

This repo has **no tests and no CI yet** — tread carefully.

```bash
# Install dependencies (creates Gemfile.lock, gitignored)
bundle install

# Build a local gem to install into a host Rails app
gem build flehmen.gemspec

# Quick sanity load (will fail if syntax errors exist in lib/)
bundle exec ruby -e 'require "flehmen"; puts Flehmen::VERSION'

# Run the STDIO server against a Rails app (requires that app's environment)
RAILS_APP_PATH=/path/to/host/app bundle exec bin/flehmen
```

There is no Rakefile, no `.rubocop.yml`, and no CI configuration. If you add
specs, scaffold them under `spec/` with a `spec_helper.rb` that stubs or
provides an ActiveRecord connection (sqlite3 is already in the Gemfile for
this reason). Do not add lint/format configs or task runners without a clear
reason — the project is intentionally minimal.

Ruby style in this repo:

- Every file uses `# frozen_string_literal: true`.
- Two-space indentation.
- Methods use keyword arguments at public boundaries (see all tools).
- Instance state on registered classes (`Configuration`, `ModelRegistry`,
  `FieldFilter`) is built in the constructor from the passed-in config; do
  not reach into `Flehmen.configuration` from inside helper classes once
  they're initialized (pass it in — see `QueryBuilder.new(model_info)` and
  `FieldFilter.new(config)`).

## Editing checklist

Before committing changes to this repo, sanity-check:

- [ ] Did you keep every query path inside `while_preventing_writes`? (i.e.
      still inheriting from `Tools::Base` and not calling `ActiveRecord` in
      unusual places like `initialize`?)
- [ ] Did you validate any new user-supplied field names / operators against
      an allowlist?
- [ ] Did you run record data through `Serializer` / `FieldFilter` before
      returning it?
- [ ] If you added a tool, is it both `require_relative`'d and registered in
      `Flehmen.register_tools`?
- [ ] If you added a config option, is it documented in `README.md`?
- [ ] Did you update `lib/flehmen/version.rb` if the change is
      user-visible? (Gem is pre-1.0 — bumping is judgment-based, but
      mention it in the PR.)

## Things to avoid

- Do not reintroduce raw-SQL execution, `find_by_sql`, string interpolation
  into `where`, or an `enable_raw_sql` toggle. This was explicitly removed.
- Do not add write-capable tools without an explicit design discussion —
  this gem's positioning is "safe read-only introspection."
- Do not broaden `ALLOWED_OPERATORS` without thinking through the Arel /
  type-coercion surface.
- Do not assume Rails 8. Dependencies are pinned to `~> 7.0`.
- Do not commit `Gemfile.lock` (it is `.gitignore`d — this is a gem, not an
  app).
- Do not create `*.md` docs or `README` updates unless asked.
