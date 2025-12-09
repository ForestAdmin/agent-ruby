# SSE (Server-Sent Events) in Ruby RPC Codebase - Comprehensive Analysis

## Overview
Server-Sent Events (SSE) is implemented in this Ruby ForestAdmin RPC codebase to enable:
1. **RPC Agent Server**: Streaming heartbeats and server stop notifications to connected datasources
2. **RPC Datasource Client**: Consuming SSE stream to monitor RPC server status and trigger schema reloads
3. **Cache Invalidation**: Listening to cache invalidation events from ForestAdmin server

---

## Files Related to SSE

### Core SSE Implementation Files

#### 1. **RPC Agent Package** (`forest_admin_rpc_agent`)
   - **Server-side SSE streaming**

| File | Purpose |
|------|---------|
| `/packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/routes/sse.rb` | Main SSE route handler for Rails/Sinatra |
| `/packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/sse_connection_manager.rb` | Manages single active SSE connection |
| `/packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/sse_streamer.rb` | Formats SSE event output |

#### 2. **RPC Datasource Package** (`forest_admin_datasource_rpc`)
   - **Client-side SSE consumption**

| File | Purpose |
|------|---------|
| `/packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/Utils/sse_client.rb` | SSE client with reconnection logic |
| `/packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/datasource.rb` | Datasource cleanup integration |
| `/packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc.rb` | Initialization and SSE client setup |

#### 3. **Agent Package** (`forest_admin_agent`)
   - **Cache invalidation via SSE**

| File | Purpose |
|------|---------|
| `/packages/forest_admin_agent/lib/forest_admin_agent/services/sse_cache_invalidation.rb` | SSE consumer for cache invalidation events |

### Test Files

| File | Coverage |
|------|----------|
| `/packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/routes/sse_spec.rb` | SSE route registration & streaming |
| `/packages/forest_admin_rpc_agent/spec/lib/forest_admin_rpc_agent/sse_connection_manager_spec.rb` | Connection management & thread safety |
| `/packages/forest_admin_datasource_rpc/spec/lib/forest_admin_datasource_rpc/utils/sse_client_spec.rb` | Client connection, errors, reconnection |
| `/packages/forest_admin_agent/spec/lib/forest_admin_agent/services/sse_cache_invalidation_spec.rb` | Cache invalidation logic |

---

## Key Classes and Methods

### 1. SSE Route Handler (`Routes::Sse`)

**Location**: `/packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/routes/sse.rb`

**Initialization**:
```ruby
Sse.new(url = 'sse', method = 'get', name = 'rpc_sse', heartbeat_interval: 10)
```

**Key Methods**:
- `registered(app)`: Detects Rails/Sinatra and registers appropriate handler
- `register_sinatra(app)`: Registers Sinatra route with streaming
- `register_rails(router)`: Registers Rails route with streaming

**Behavior**:
- Streams `heartbeat` events every `heartbeat_interval` seconds (default: 10s)
- Sends `RpcServerStop` event when server shuts down
- Uses `text/event-stream` content type
- Sets headers: `Cache-Control: no-cache`, `Connection: keep-alive`, `X-Accel-Buffering: no`
- Authenticates via `ForestAdminRpcAgent::Middleware::Authentication`
- Manages signal handlers (SIGINT, SIGTERM) for graceful shutdown

### 2. SSE Connection Manager (`SseConnectionManager`)

**Location**: `/packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/sse_connection_manager.rb`

**Class Methods**:
- `register_connection()`: Creates new connection, terminates previous one
- `unregister_connection(connection)`: Marks connection as ended
- `current_connection()`: Returns active connection (for testing)
- `reset!()`: Clears all connections (for testing)

**Thread Safety**:
- Uses `Mutex` for all state access
- Ensures only ONE active SSE connection at a time
- Terminates zombie connections on reconnection

**Connection Object**:
```ruby
class Connection
  @id          # UUID string
  @active      # Boolean flag, protected by mutex
  
  def active?      # Thread-safe check
  def terminate     # Thread-safe termination
end
```

### 3. SSE Streamer (`SseStreamer`)

**Location**: `/packages/forest_admin_rpc_agent/lib/forest_admin_rpc_agent/sse_streamer.rb`

**Simplest Component**:
```ruby
class SseStreamer
  def write(object, event: nil)
    @yielder << "event: #{event}\n" if event
    @yielder << "data: #{JSON.dump(object)}\n\n"
  end
end
```

### 4. SSE Client (`Utils::SseClient`)

**Location**: `/packages/forest_admin_datasource_rpc/lib/forest_admin_datasource_rpc/Utils/sse_client.rb`

**Initialization**:
```ruby
SseClient.new(uri, auth_secret, &on_rpc_stop)
```

**Public Methods**:
- `start()`: Begin connection attempt
- `close()`: Gracefully close connection
- `closed`: Attribute reader (boolean)

**Private Methods**:
- `attempt_connection()`: Establishes SSE connection
- `handle_event(event)`: Processes incoming events (heartbeat, RpcServerStop)
- `handle_error_with_reconnect(err)`: Handles errors with reconnection
- `schedule_reconnect()`: Schedules reconnection in background thread
- `calculate_backoff_delay()`: Exponential backoff (2s, 4s, 8s, 16s, 30s max)
- `generate_signature(timestamp)`: HMAC-SHA256 authentication

**Key Features**:
- Exponential backoff reconnection (2 to 30 seconds max)
- Authenticates via `X_TIMESTAMP` + `X_SIGNATURE` headers
- Distinguishes auth errors (401/403) from connection errors
- Calls callback on `RpcServerStop` event
- Resets connection attempts counter on stable heartbeat
- Thread-safe connection state management

### 5. SSE Cache Invalidation (`Services::SSECacheInvalidation`)

**Location**: `/packages/forest_admin_agent/lib/forest_admin_agent/services/sse_cache_invalidation.rb`

**Purpose**: 
- Listens to ForestAdmin server's SSE events
- Invalidates local caches based on event type

**Event Mapping**:
```ruby
MESSAGE_CACHE_KEYS = {
  'refresh-users': %w[forest.users],
  'refresh-roles': %w[forest.collections],
  'refresh-renderings': %w[forest.collections forest.rendering]
}
```

---

## Architecture & Integration Points

### 1. RPC Agent as Server (Streams SSE)

```
┌─────────────────────────────────────────┐
│  ForestAdminRpcAgent (Server)           │
├─────────────────────────────────────────┤
│ Routes::Sse                             │
│  - URL: /sse                            │
│  - Auth: Middleware::Authentication     │
│  - Output: SseStreamer                  │
├─────────────────────────────────────────┤
│ SseConnectionManager                    │
│  - Ensures 1 active connection          │
│  - Terminates previous connections      │
├─────────────────────────────────────────┤
│ Events:                                 │
│  - heartbeat (every 10s)                │
│  - RpcServerStop (on shutdown)          │
└─────────────────────────────────────────┘
```

### 2. RPC Datasource as Client (Consumes SSE)

```
┌──────────────────────────────────────────┐
│ ForestAdminDatasourceRpc                 │
├──────────────────────────────────────────┤
│ SseClient (Utils)                        │
│  - URI: {rpc_uri}/forest/sse             │
│  - Auth: HMAC-SHA256 signature           │
│  - Library: ld-eventsource ~> 2.2        │
├──────────────────────────────────────────┤
│ Event Handlers:                          │
│  - heartbeat → ignore, reset attempts    │
│  - RpcServerStop → trigger callback      │
├──────────────────────────────────────────┤
│ Error Handling:                          │
│  - Auth errors (401/403) → reconnect     │
│  - Connection errors → exponential backoff│
│  - Max backoff: 30 seconds               │
├──────────────────────────────────────────┤
│ Datasource::cleanup()                    │
│  - Called on exit/SIGINT/SIGTERM         │
│  - Gracefully closes SSE client          │
└──────────────────────────────────────────┘
```

### 3. Cache Invalidation Service

```
┌────────────────────────────────────────┐
│ ForestAdminAgent                        │
├────────────────────────────────────────┤
│ SSECacheInvalidation service            │
│  - URI: {server}/liana/v4/subscribe-to-│
│         events                          │
│  - Auth: forest-secret-key header       │
│  - Library: ld-eventsource ~> 2.2       │
├────────────────────────────────────────┤
│ Processes events:                       │
│  - refresh-users → invalidate users     │
│  - refresh-roles → invalidate collections
│  - refresh-renderings → invalidate both │
└────────────────────────────────────────┘
```

---

## Workflow: RPC Server Stop & Schema Reload

### Sequence Diagram

```
1. Master restarts
   │
2. New datasource connection established
   ├─ ForestAdminDatasourceRpc.build() called
   ├─ SseClient created
   ├─ SseClient.start() called
   └─ Background reconnection thread started
   │
3. RPC server listener registered (Routes::Sse)
   ├─ SseConnectionManager::register_connection()
   ├─ Previous connection marked as terminated
   └─ Heartbeats begin streaming
   │
4. On RPC server shutdown
   ├─ SIGTERM/SIGINT trapped
   ├─ SseStreamer sends RpcServerStop event
   └─ Connection closes
   │
5. SseClient detects RpcServerStop
   ├─ Event handler invoked
   ├─ on_rpc_stop callback executed
   ├─ New schema fetched
   ├─ Schema hash compared (Digest::SHA1)
   └─ If changed → AgentFactory.reload!
```

---

## External Dependencies

### 1. ld-eventsource ~> 2.2

**Package**: Both `forest_admin_agent` and `forest_admin_datasource_rpc`

**Usage**:
```ruby
require 'ld-eventsource'

SSE::Client.new(uri, headers: {...}) do |client|
  client.on_event { |event| handle_event(event) }
  client.on_error { |err| handle_error(err) }
end
```

**Features Used**:
- `SSE::Client` - HTTP client for Server-Sent Events
- `SSE::Errors::HTTPStatusError` - HTTP-specific errors

---

## Security & Authentication

### Server-Side (RPC Agent)
1. **Middleware Authentication** (`Middleware::Authentication`)
   - Validates `X_TIMESTAMP` and `X_SIGNATURE` headers
   - HMAC-SHA256 based signature verification
   - Replay attack protection via used signatures cache

### Client-Side (RPC Datasource)
1. **HMAC-SHA256 Signature**
   - `X_TIMESTAMP`: ISO8601 timestamp with millisecond precision
   - `X_SIGNATURE`: HMAC-SHA256(secret, timestamp)
   - Sent with every connection attempt

2. **Cache Invalidation Service**
   - Uses `forest-secret-key` header
   - Server-side authentication

---

## Error Handling & Resilience

### Connection Failures

```ruby
Exponential Backoff Strategy:
- Attempt 1 → 2 seconds
- Attempt 2 → 4 seconds
- Attempt 3 → 8 seconds
- Attempt 4 → 16 seconds
- Attempt 5+ → 30 seconds (capped)
- Auth errors (401/403) → +2 attempts boost
```

### Error Types Handled

| Error | Behavior | Log Level |
|-------|----------|-----------|
| Auth (401/403) | Reconnect with backoff | Debug |
| EOFError, IOError | Reconnect with backoff | Debug |
| HTTPStatusError (others) | Reconnect with backoff | Warn |
| StandardError | Reconnect with backoff | Warn |

### Graceful Shutdown

```ruby
Signal Handlers:
- SIGINT (Ctrl+C)   → cleanup() → exit(0)
- SIGTERM (kill -15) → cleanup() → exit(0)
- at_exit hook       → cleanup()
```

---

## Event Format (SSE Protocol)

### Heartbeat Event
```
event: heartbeat
data: {}

```

### RpcServerStop Event
```
event: RpcServerStop
data: {"event":"RpcServerStop"}

```

### Unknown Event (logged)
```
event: SomeEvent
data: {...payload...}

```

---

## Testing Coverage

### 1. Connection Manager Tests
✅ Single active connection enforcement
✅ Previous connection termination
✅ Concurrent registration safety
✅ Connection ID uniqueness
✅ Thread-safe state access

### 2. SSE Route Tests
✅ Rails route registration
✅ Sinatra route registration
✅ Heartbeat streaming
✅ Custom heartbeat intervals
✅ Correct SSE headers
✅ Signal handling
✅ Client disconnection handling
✅ IOError/EPIPE handling
✅ Connection manager integration

### 3. SSE Client Tests
✅ Connection establishment with auth headers
✅ Exponential backoff calculation
✅ Heartbeat handling (resets attempt counter)
✅ RpcServerStop callback execution
✅ HTTP error detection (401/403)
✅ Connection lost detection (EOFError, IOError)
✅ Graceful close
✅ Reconnection thread management
✅ Event type/data whitespace stripping

### 4. Cache Invalidation Tests
✅ Event type mapping
✅ Cache key invalidation
✅ Error handling

---

## Current Branch: `fix/rpc-agent-404-json-response`

Recent commits show focus on:
1. RPC agent 404 JSON response handling
2. Mock fixes for handler proc capture
3. RuboCop violation fixes
4. Explicit begin/rescue blocks in register_rails

---

## Key Statistics

- **Total SSE-related files**: 10 (6 implementation + 4 spec)
- **Lines of code**: ~900 (core implementation)
- **Packages affected**: 2 (rpc_agent, datasource_rpc, agent)
- **External library**: ld-eventsource ~> 2.2
- **Protocol**: Server-Sent Events (text/event-stream)
- **Auth method**: HMAC-SHA256
- **Max reconnection delay**: 30 seconds
- **Default heartbeat interval**: 10 seconds

---

## Integration Summary

### RPC Agent Package Flow
```
1. Routes::Sse registered via Http::Router
2. Authentication checked via Middleware::Authentication
3. SseConnectionManager ensures single connection
4. Events streamed via SseStreamer
5. Signal handlers ensure graceful shutdown
```

### RPC Datasource Package Flow
```
1. ForestAdminDatasourceRpc.build() creates SseClient
2. SseClient connects with HMAC-SHA256 auth
3. Background thread handles reconnection with backoff
4. RpcServerStop triggers schema reload callback
5. Datasource::cleanup() closes SSE connection
```

### Agent Package Flow
```
1. SSECacheInvalidation.run() connects to server SSE
2. Listens for refresh-* events
3. Invalidates appropriate cache keys
4. Handles SSE connection errors gracefully
```

