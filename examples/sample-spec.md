# Example Specification File

This is a sample specification file for use with `copilot-supervisor.ps1`.

## Requirements

### Feature: User Authentication

**Description**: Implement a user authentication system with login and logout functionality.

**Requirements**:
1. Create a `/login` endpoint that accepts username and password
2. Return a JWT token on successful authentication
3. Implement a `/logout` endpoint to invalidate tokens
4. Add middleware to protect authenticated routes
5. Store user credentials securely with bcrypt hashing

**Acceptance Criteria**:
- Login endpoint returns 200 with JWT on success, 401 on failure
- Logout endpoint returns 200 and invalidates the token
- Protected routes return 401 without valid token
- Passwords are never stored in plaintext
- All endpoints have proper error handling

### Feature: Data Validation

**Description**: Implement input validation for all user-facing endpoints.

**Requirements**:
1. Validate email format for email fields
2. Enforce password strength requirements (min 8 chars, 1 uppercase, 1 number)
3. Sanitize all user input to prevent XSS attacks
4. Return clear error messages for validation failures

**Acceptance Criteria**:
- Invalid emails are rejected with 400 status
- Weak passwords are rejected with clear requirements
- XSS attempts are sanitized
- Error messages are user-friendly

### Code Quality Standards

- Follow language-specific style guides
- Add unit tests with >80% coverage
- Include JSDoc/docstring comments for public APIs
- Use meaningful variable and function names
- Keep functions under 50 lines where possible

### Security Requirements

- Use parameterized queries to prevent SQL injection
- Implement rate limiting on authentication endpoints
- Never log sensitive data (passwords, tokens, PII)
- Use HTTPS for all API communication
- Validate and sanitize all user input
