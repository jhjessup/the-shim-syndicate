# TEST DOCTRINE — Project Testing Specification
**Project:** `{{PROJECT_NAME}}`  
**Hydrated From:** The Shim Syndicate `v{{SYNDICATE_VERSION}}`  
**Established:** `{{HYDRATION_DATE}}`  
**Authority:** The Gavel (`@gavel`)

---

> **What is the Test Doctrine?**  
> The Test Doctrine is the project-specific specification for what constitutes a valid test, how tests are structured, and what The Gavel must verify during audit. It is a supplement to the `ORACLE.md` — the Oracle defines *thresholds*, the Doctrine defines *what those thresholds measure and how to meet them*. Every agent (Lead, Ledger, Gavel, Operative) reads this file when making decisions about test generation, test coverage, and audit verdicts. Placeholder sections (marked `{UPPER_SNAKE_CASE}` with double braces) must be filled before committing — unfilled tokens are treated as a Gavel FAIL.

---

## 1. Test Taxonomy

The following four test types are the only recognized categories in this project. All tests must be classifiable into exactly one type. Tests that cannot be classified are considered malformed and constitute a `[MED]` finding.

### 1.1 Type Definitions

| Type | Label | Purpose | Required Fixtures | HTTP Layer? |
|------|-------|---------|-------------------|-------------|
| **Unit** | `@unit` | Validates a single function's logic and return value in isolation | Database session + typed input args | ❌ Never |
| **Service** | `@service` | Validates a service function's side effects on persistent state | Database session + domain model instances | ❌ Never |
| **Endpoint** | `@endpoint` | Validates an HTTP route's request/response contract | Authenticated HTTP client | ✅ Always |
| **Integration** | `@integration` | Validates composition across two or more service boundaries | Full stack — session + domain models + HTTP client | ✅ Required |

### 1.2 Type Rules

- **Unit tests** must not import or instantiate an HTTP client. If a test requires an `AsyncClient`, it is at minimum an Endpoint test.
- **Service tests** must assert on database state directly — not on HTTP response bodies. If the only assertion is on a response body, it is an Endpoint test.
- **Endpoint tests** must test exactly one route. Multi-route flows belong in Integration tests.
- **Integration tests** must cross at least one service boundary and assert on the side effects of the composition, not just the final response.

### 1.3 Test Marking

All tests must carry the appropriate pytest mark:

```python
@pytest.mark.unit
@pytest.mark.service
@pytest.mark.endpoint
@pytest.mark.integration
```

Marks must be registered in `pyproject.toml` under `[tool.pytest.ini_options] markers`. Unmarked tests constitute a `[LOW]` finding per test; a test suite with >10% unmarked tests constitutes a `[MED]` finding.

---

## 2. Composability Axioms

Composability axioms define the structural contracts that make a service function independently testable. They are architectural rules, not style preferences. Violations are audit findings.

### 2.1 Universal Axioms

These axioms apply to every Syndicate project regardless of domain:

**AX-1 — HTTP Independence**  
Every service function must be callable with only a database session and typed arguments. No service function may require an HTTP request object, response object, or HTTP client as a parameter.

**AX-2 — Explicit Side Effect Declaration**  
Every service function that writes to the database as a side effect (beyond its primary return value) must document those side effects in its docstring under a `Side Effects:` heading. Undocumented side effects constitute a `[MED]` finding.

**AX-3 — Single Composition Seam**  
Service functions may call other service functions. When they do, the calling function owns the composition contract — it is responsible for ensuring its callee's side effects are covered by at least one Service test. A composition that is tested only through an HTTP endpoint constitutes a `[HIGH]` finding.

**AX-4 — Direct Testability Requirement**  
Every service function introduced by an Operative must have at least one Unit or Service test that calls it directly — without routing through an HTTP endpoint. This is not a coverage metric; it is a structural requirement. A new service function with no direct test is a `[HIGH]` Gavel finding regardless of endpoint test coverage.

**AX-5 — No Fixture Duplication**  
Test utilities (cursor helpers, factory functions, assertion helpers) must not be duplicated across test modules. Shared utilities belong in a dedicated `tests/utils/` or `conftest.py`. Duplication of utility logic across more than two modules constitutes a `[MED]` finding.

### 2.2 Project-Specific Axioms

```
{{PROJECT_COMPOSABILITY_AXIOMS}}
```

---

## 3. Coverage Contract

### 3.1 Coverage Thresholds by Layer

```
{{COVERAGE_THRESHOLDS}}
```

Coverage is measured per layer, not as a global aggregate. A project that meets global 80% while having 0% service-direct coverage is non-compliant.

### 3.2 Mandatory Test Matrix

The following behaviors are **categorically required** regardless of coverage metrics. Each must have a named test that explicitly validates the behavior. Missing tests for any item in this matrix constitute a `[CRIT]` Gavel finding — they are not addressable by coverage percentage.

```
{{MANDATORY_TEST_MATRIX}}
```

### 3.3 Error Path Requirements

Every endpoint must have at minimum one test for each of the following response codes that it can return:

- `400 Bad Request` — Invalid input; malformed payload
- `401 Unauthorized` — Missing or expired authentication
- `403 Forbidden` — Valid authentication, insufficient role
- `404 Not Found` — Resource does not exist or is access-controlled
- `409 Conflict` — Constraint violation (duplicate key, state conflict)

Endpoints with no error path tests constitute a `[MED]` finding per missing code.

---

## 4. Gavel Audit Criteria for Tests

When The Gavel audits a pull request or commit that includes new or modified tests, the following criteria apply. These criteria are additive to the standard Code Quality Audit checklist in `THE_GAVEL.md`.

### 4.1 New Service Function Gate

For every new service function in a staged diff:

| Check | Severity if Missing |
|-------|---------------------|
| Has at least one Unit or Service test calling it directly | `[HIGH]` |
| Has documented side effects in docstring (if it writes to DB) | `[MED]` |
| Side effects are asserted on in at least one Service test | `[HIGH]` |
| Error paths (invalid input, not found) have at least one test each | `[MED]` |

### 4.2 New Endpoint Gate

For every new API endpoint in a staged diff:

| Check | Severity if Missing |
|-------|---------------------|
| Has at least one Endpoint test for the happy path | `[HIGH]` |
| Has Endpoint tests for 401, 403 (if RBAC applies) | `[HIGH]` |
| Has Endpoint tests for 400 (if request body is validated) | `[MED]` |
| The underlying service function has a direct test (AX-4) | `[HIGH]` |

### 4.3 Mandatory Matrix Gate

For any commit that touches code related to a Mandatory Test Matrix item (§3.2):

| Check | Severity if Missing |
|-------|---------------------|
| The named matrix test exists | `[CRIT]` |
| The named matrix test still passes | `[CRIT]` |
| The matrix test asserts on the correct behavior (not just status code) | `[HIGH]` |

### 4.4 Test Quality Indicators

The Gavel must flag the following as findings even when tests exist:

| Pattern | Severity |
|---------|---------|
| Test asserts only on HTTP status code, not on response body or DB state | `[MED]` |
| Test uses `assert True` or trivially-passing assertion | `[HIGH]` |
| Test fixture has session scope but mutates state | `[HIGH]` |
| Test duplicates fixture logic already in `conftest.py` | `[LOW]` |
| Test file has no type annotations on fixture parameters | `[LOW]` |
| Integration test makes no cross-boundary assertion | `[MED]` |

---

## 5. Test Organization Standards

### 5.1 Directory Layout

```
tests/
├── conftest.py                  # Global fixtures only — no test functions
├── utils/                       # Shared test utilities (factories, assertion helpers)
│   └── __init__.py
├── unit/                        # @unit tests — no HTTP, no HTTP client fixture
├── service/                     # @service tests — direct service function calls + DB assertions
├── endpoint/                    # @endpoint tests — HTTP route contract tests
│   └── conftest.py              # HTTP client fixtures
└── integration/                 # @integration tests — cross-boundary workflow tests
```

### 5.2 Fixture Scoping Rules

| Fixture | Permitted Scope | Reason |
|---------|-----------------|--------|
| Database engine | `session` | Expensive to create; shared across all tests |
| Database session | `function` | Must be isolated — transactions rolled back per test |
| HTTP client | `function` | State must not bleed between tests |
| Domain model instances | `function` | Mutable state — never session-scoped |
| RSA keys / JWT tokens | `session` | Read-only; safe to share |
| Batch seed data | `function` | Must be regenerated to avoid cross-test contamination |

### 5.3 Naming Conventions

- Test functions: `test_<behavior>_<condition>_<expected_result>()`
  - Example: `test_get_patient_when_private_returns_404()`
  - Example: `test_create_medication_with_duplicate_idempotency_key_returns_original()`
- Fixture functions: descriptive nouns, no `test_` prefix
  - Example: `authenticated_client`, `db_session`, `test_patient`

---

## 6. Doctrine Version History

| Version | Changed By | Date | Summary |
|---------|------------|------|---------|
| 1.0 | {{OPERATOR_NAME}} | {{HYDRATION_DATE}} | Initial Test Doctrine established from Syndicate template |

---

*This Test Doctrine is project-local and lives in `.syndicate/TEST_DOCTRINE.md`. It is referenced by `ORACLE.md` §4 and read by The Gavel at audit time. Do not modify the universal axioms (§2.1) without a corresponding Syndicate Core version bump. Project-specific sections (§2.2, §3.1, §3.2) may be updated by The Lead with operator sign-off, logged in `AUDIT_LOG.md`.*
