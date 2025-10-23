# Forest Admin Agent Ruby - Error Handling

This document describes the improved error handling system in Forest Admin Agent Ruby, which mimics the error handling approach from agent-nodejs.

## Overview

The new error handling system provides:

1. **Explicit error types** - Clear, specific error classes for different scenarios
2. **Proper HTTP status codes** - Automatic mapping of business errors to appropriate HTTP status codes
3. **Rich error information** - Support for error details, metadata, and custom headers
4. **Better debugging** - More informative error messages for developers

## Error Hierarchy

### BusinessError (Base Class)

All business errors inherit from `BusinessError`, which provides:
- `message` - The error message
- `details` - A hash of additional details/metadata
- `cause` - The underlying cause (if any)
- `name` - The error class name

### Common Error Classes

The system provides error classes for all standard HTTP error codes:

#### 4xx Client Errors

- `BadRequestError` (400) - Invalid request data
- `ForbiddenError` (403) - Insufficient permissions
- `NotFoundError` (404) - Resource not found
- `ConflictError` (409) - Resource conflict
- `UnprocessableError` (422) - Validation failed
- `TooManyRequestsError` (429) - Rate limit exceeded

#### 5xx Server Errors

- `InternalServerError` (500) - Unexpected server error
- `BadGatewayError` (502) - Bad gateway
- `ServiceUnavailableError` (503) - Service temporarily unavailable

### Specialized Error Classes

#### Authentication Errors (all 401)

- `InvalidApplicationTokenError`
- `InvalidCredentialsError`
- `InvalidRecoveryCodeError`
- `InvalidRefreshTokenError`
- `InvalidSessionHashError`
- `InvalidTimeBasedPasswordError`
- `InvalidTokenError`
- `InvalidUserError`
- `MissingTokenError`
- `PasswordLoginUnavailableError`
- `TwoFactorAuthenticationRequiredError`

#### Authorization Errors (all 403)

- `TwoFactorAuthenticationRequiredForbiddenError`

#### Extended Common Errors

- `EntityNotFoundError` - Extends `NotFoundError` with entity name support
- `ValidationFailedError` - Extends `BadRequestError` for validation errors

## Usage Examples

### Basic Error Raising

```ruby
# Raise a simple forbidden error
raise ForestAdminAgent::Http::Exceptions::ForbiddenError.new(
  "You don't have permission to access this resource"
)

# Raise a not found error with details
raise ForestAdminAgent::Http::Exceptions::EntityNotFoundError.new(
  'User',
  details: { user_id: 123 }
)

# Raise an authentication error
raise ForestAdminAgent::Http::Exceptions::InvalidTokenError.new

# Raise a validation error with details
raise ForestAdminAgent::Http::Exceptions::ValidationFailedError.new(
  'Validation failed',
  details: {
    field: 'email',
    error: 'Email is required'
  }
)
```

### Error with Custom Details

```ruby
raise ForestAdminAgent::Http::Exceptions::ConflictError.new(
  'An organization with this name already exists',
  details: {
    organization_name: 'Acme Corp',
    suggestion: 'Try a different name'
  }
)
```

### Error with Cause

```ruby
begin
  external_service.call
rescue StandardError => e
  raise ForestAdminAgent::Http::Exceptions::ServiceUnavailableError.new(
    'External service is unavailable',
    details: { service: 'external_api' },
    cause: e
  )
end
```

### Rate Limiting Error

```ruby
raise ForestAdminAgent::Http::Exceptions::TooManyRequestsError.new(
  'Too many requests',
  60, # retry_after in seconds
  details: { limit: 100, period: '1 minute' }
)
```

## Error Response Format

Errors are automatically converted to JSON responses with the following format:

```json
{
  "errors": [
    {
      "name": "ForbiddenError",
      "detail": "You don't have permission to access this resource",
      "status": 403,
      "meta": {
        "resource": "users",
        "action": "delete"
      }
    }
  ]
}
```

## Custom Headers

Some errors automatically add custom headers to the response:

- `NotFoundError` adds `x-error-type: object-not-found`
- `TooManyRequestsError` adds `Retry-After: <seconds>`

## Backward Compatibility

The new system is backward compatible with existing code:

- Old `HttpException`-based errors still work
- Legacy error signatures are supported
- The error handling middleware automatically translates both old and new errors

## Migration Guide

To migrate existing code to use the new error system:

### Before

```ruby
raise ForbiddenError.new("Access denied", "ForbiddenError")
```

### After

```ruby
raise ForestAdminAgent::Http::Exceptions::ForbiddenError.new(
  "Access denied"
)
```

### Before

```ruby
raise StandardError, "Something went wrong"
```

### After

```ruby
raise ForestAdminAgent::Http::Exceptions::InternalServerError.new(
  "Something went wrong",
  details: { context: 'additional info' }
)
```

## Benefits

1. **Type Safety** - Specific error classes make it clear what error is being raised
2. **Automatic HTTP Mapping** - No need to manually set status codes
3. **Rich Debugging Info** - Details field provides context without exposing sensitive data
4. **Consistent API** - All errors follow the same pattern
5. **Better Testing** - Easy to test specific error types

## Implementation Details

The error handling system consists of:

1. **BusinessError classes** (`business_error.rb`) - Base error classes
2. **HttpError wrapper** (`http_error.rb`) - Wraps business errors with HTTP-specific properties
3. **ErrorTranslator** (`error_translator.rb`) - Maps business errors to HTTP status codes
4. **ErrorHandling module** (`error_handling.rb`) - Helper methods for error responses
5. **Rails Controller** - Automatically catches and formats errors

All errors are automatically caught by the `ForestController` and converted to appropriate JSON responses.
