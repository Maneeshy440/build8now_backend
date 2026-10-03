# Security Notes

## Password hashing and JWT
- Passwords are hashed using bcrypt via `bcryptjs` before insertion.
- JWTs are signed with `JWT_SECRET` and `JWT_EXPIRES_IN` and should be stored in secure client storage.
- Logout and refresh are not yet implemented in this minimal backend foundation; production use should include refresh-token rotation and revocation support.

## Authorization
- Admin, customer, and influencer roles are enforced through middleware.
- Object-level checks ensure a customer can only view their own orders and an influencer can access only their own balance/ledger.
- `401` is returned for missing/invalid tokens and `403` for insufficient permissions.

## Input validation
- Request payloads are validated for required fields and structurally expected values.
- Email and role checks are performed before user registration.

## SQL injection prevention
- All SQL queries use parameterized statements (`?` placeholders) instead of string interpolation.

## Sensitive data protection
- Secrets remain in `.env` and are not committed to source control.
- Password hashes and JWTs are never returned in API responses.
- Application logs should avoid logging raw passwords or tokens in production.

## Additional protections
- Helmet is enabled for security headers.
- CORS is enabled with credentials support for a basic web-facing setup.
- Rate limiting is enabled to reduce abuse and brute-force attempts.
