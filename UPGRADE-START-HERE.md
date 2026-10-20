# GridSync functional upgrade

The original public page, ivory/forest/lime palette, typography, cards, responsive styles and CSS 3D depot are retained. New `/login`, `/customer` and `/manager` routes extend that design. Login and manager scenes reuse the local CSS geometry, gentle animation and pointer interaction. Reduced-motion preferences are respected; WebGL is not required.

This edition adds Supabase authentication, vehicle management, compatible reservations, charging lifecycle controls, substation capacity allocation, tariff management, persistent test payments and server-generated invoice PDFs. Authenticated dashboards use database records. The original public page remains an explicitly labelled interactive demo.

## Install and migrate

Use Node.js 22 or 24. From the extracted project folder:

```sh
npm ci
```

Copy `.env.example` to `.env`. Set `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `APP_ORIGIN=http://localhost:3000`. No service-role key is needed. The API uses the anonymous project key with the signed-in user's access token and database row-level security.

Back up an existing database, then use the Supabase SQL Editor as an administrator:

1. For a **new empty project**, run `sql/supabase_schema.sql` once. It creates PostgreSQL tables and illustrative legacy seed records. Do not run the SQL Server/T-SQL scripts against Supabase.
2. For a project that **already has that PostgreSQL schema**, skip the base script and retain its data.
3. In either case, run `sql/migrations/20261019_secure_workflows.sql` **once**, in full. It is transactional and records its version in `gs_migration`. A second run intentionally fails.

The migration adds fields, policies, RPCs and auth mappings without deleting legacy records. It removes anonymous table access and client grants on legacy operational views. If duplicate historical invoices, payment references, active bays/vehicles or registrations prevent unique indexes from being created, the migration rolls back. Reconcile those specific records before retrying; no automatic deletion/merge is performed.

## Authentication and manager accounts

### Editable demo with normal login and registration

Choose **Admin demo login** or **Customer demo login** on the login page. This selects demo mode and fills the ordinary email/password form; press **Sign in to demo workspace** to authenticate the demo account. No Supabase setup is required for demo mode.

| Demo account | Email | Password |
| --- | --- | --- |
| Admin / manager | `admin@demo.gridsync.test` | `DemoAdmin123!` |
| Customer | `customer@demo.gridsync.test` | `DemoCustomer123!` |

These credentials work only in the browser-local demo. They are not production accounts and are not accepted by the real backend. In demo mode, **Create account** registers a new demo customer using the form. Use a dummy password. After registering, sign in using the credentials you chose. Demo registration sends no email and cannot create an admin role.

The demo now starts from the project's **original `sql/supabase_schema.sql` example database**: 4 stations, 12 charger bays, 3 substations, 10 vehicles, 13 user records, 3 fleet organizations, 8 missions and 7 reservations. IDs, relationships, capacities, registrations and organization assignments are retained. The built-in admin maps to original user #1; the built-in customer maps to Arjun Singh (#6), who has two original vehicles. Other customers' vehicles remain visible to the admin, not the customer account.

The original SQL does not seed tariffs, sessions, invoices or payments, and it predates vehicle make/model/connector fields. Those are supplemented with clearly simulated demo examples: 4 editable tariffs, 5 session examples, 2 invoices and a sample test transaction, plus illustrative vehicle model/connector specifications. They are not claimed to be verified real vehicle specifications or original SQL billing records. Relative booking/mission times are rebased when the demo is first initialized/reset, so future examples remain usable.

`frontend/demo-seed.js` is generated from the actual SQL using `npm run demo:seed` (requires development dependencies). This is a browser-local copy of the example dataset; it does not connect demo users to your live Supabase database. The expanded dataset uses a new storage version, leaving the older small demo's saved data untouched. Previously registered accounts in that older demo version must be registered again in the expanded sandbox.

The demo is fully editable: add/edit/archive vehicles, reserve/cancel bays, request charging, update your profile, and view/pay invoices. Admins can manage stations/connectors/substations/tariffs, start sessions, record simulated readings, complete/fail charging, issue the resulting invoices, schedule missions and simulate payment refunds. Ownership and role checks apply inside the demo adapter; customers see their own records and admins see the demo installation.

To try the full cycle, register a demo customer, add a compatible vehicle and request a simulated session. Sign out, use the admin demo account to start/meter/complete that request, then sign back in as the customer to simulate payment and download the demo invoice. The invoice uses the saved demo session and pricing data and is clearly marked **DEMO / SIMULATED**. All demo amounts and energy are simulated.

Changes are saved in **localStorage in this browser**, shared across demo accounts/tabs on the same site. The signed-in demo account is stored per tab. Reloading or signing out preserves saved demo records. Passwords for registered demo customers are stored as salted PBKDF2 hashes; this remains a client-side sandbox, not a production security boundary. Browser storage must be available; use HTTPS or localhost for Web Crypto support. Do not enter real personal/payment data or reuse real passwords. **Reset demo data** clears the demo records and registered demo accounts, then restores the original samples on the next login.

Choose **Use real account login** to return to Supabase authentication. No demo workflow calls the real API or grants real manager privileges. Real APIs continue enforcing Supabase authentication and database role/ownership rules. Demo PDFs are generated locally using the bundled PDF library; real invoice PDFs continue using the authorized backend workflow.

In Supabase Authentication, enable email/password accounts. Set Site URL to your local or final deployed origin, and add `<origin>/login` to allowed redirect URLs. Configure confirmation email delivery for your project.

```sh
npm start
```

Open **http://localhost:3000/login**. Create a customer account. If confirmation is enabled, confirm the email and then sign in with your chosen password. Supabase handles hashing, verification and authentication rate limits. No default production credentials exist.

Roles come from protected `app_user.role`, never from a role selector or user-editable Auth metadata. Registration always creates a customer. A trusted administrator creates a manager by first creating/confirming an ordinary account, verifying its Auth UUID, and running the following in the SQL Editor with both placeholders replaced:

```sql
UPDATE public.app_user
SET role = 'manager'
WHERE auth_user_id = 'REPLACE_WITH_VERIFIED_AUTH_UUID'::uuid
  AND email = 'verified-manager@example.com'
RETURNING user_id, email, role;
```

Confirm exactly the intended account is returned. Sign out/in. Managers redirect to `/manager`; customers to `/customer`. Managers have installation-wide operational privileges, not tenant-limited fleet privileges.

Existing seeded users do not become login accounts automatically. Existing Auth identities receive isolated customer profiles in the migration. An email match alone never grants legacy ownership. A trusted database administrator must review any transfer of historical vehicles/bookings to a verified identity; self-service claiming is intentionally unavailable.

## Infrastructure and pricing

Managers use **Substations** to verify rated capacities, baseline load, load source and allocation limits. All power values are **kW**. The baseline is non-charging load; do not double-count the same charging load.

In **Stations & tariffs**, verify station/substation assignments, IANA timezones, connector types, rated output and operational status. Add an active tariff for each station before starting a session. The upgrade does not invent or seed billable rates. Configure currency, energy rate, idle rate, tax percentage, service fee and fixed discount according to your actual pricing policy.

Tariff hours use the station timezone, inclusive start/exclusive end. `0–24` covers a whole day. Split overnight tariffs into two non-overlapping plans. A session locks the applicable tariff when charging starts and retains it through completion, including across tariff boundaries. This edition does not split a session across multiple time-of-use tariffs.

Customers add registration, make, model and verified connector support. Battery capacity and maximum power may be unknown when registering a vehicle; maximum power must be set before requesting charging. Legacy vehicles with empty connector specifications need verification before new bookings. Resolve open bookings/sessions before editing vehicle specifications.

## Charging lifecycle

1. Customers reserve a compatible connector or request a walk-in/scheduled session. Reservations check bay and vehicle overlaps and last at most 24 hours.
2. Managers start due queued/scheduled requests with an initial meter reading. Reservation-backed sessions must start inside the confirmed reservation window.
3. The database allocates the minimum of connector power, vehicle power and remaining substation capacity within the configured limit. A session stays queued when capacity is insufficient. Only one active session per bay/vehicle is allowed.
4. Managers record cumulative meter readings. Sources are **simulated** or **manual**, neither verified charger telemetry. Readings are monotonic and cannot imply energy above allocated power over the recorded duration or known battery capacity.
5. Completing a session stops charging, releases capacity, completes its reservation and generates one invoice in the same transaction. Failing an active session requires a reason; delivered energy is invoiced if greater than zero. Queued/scheduled requests can be cancelled with a reason.

For a quick test, choose simulated metering, start at `100 kWh`, and record `110 kWh` with `3600` total simulated seconds, provided allocated power is at least `10 kW`. This represents **10 simulated kWh over one simulated hour** and does not wait an hour. A synthetic end timestamp may therefore be later than wall-clock time; simulation is labelled throughout.

Manual sessions use wall-clock duration. Simulation time is cumulative, monotonic and capped at seven days. Idle duration cannot exceed total duration or leave insufficient charging time for the recorded energy. Grid load is baseline plus active allocated power, with simulated-session counts shown. Refresh retrieves new data on demand; it is not live grid monitoring.

No OCPP/hardware command integration, automatic queue worker or continuous redistribution is claimed. Managers control the application lifecycle. Capacity limits affect newly started sessions; active allocations remain until completion/failure. Critical operations use a transaction advisory lock, intentionally serializing changes for this small project rather than claiming a high-throughput distributed scheduler.

## Invoices and test payments

PostgreSQL numeric arithmetic computes:

```text
energy = round(delivered kWh × locked rate, 2)
idle = round(idle minutes × locked rate, 2)
discount = min(configured discount, energy + idle + service fee)
tax = round((energy + idle + service fee − discount) × tax percent / 100, 2)
total = energy + idle + service fee − discount + tax
```

Customer/vehicle/station details, meter readings and tariff are snapshotted at invoice issuance, preserving historical billing when profiles change. PDFs are generated on the backend from these stored values after ownership authorization. Payment state and transaction details are read from current records. Legacy invoices without a billing snapshot require administrator reconciliation rather than fabricated PDF details.

Configure `INVOICE_ISSUER` and `INVOICE_ISSUER_ADDRESS`. These are operational invoices; review jurisdiction-specific issuer/tax-registration fields and accounting requirements before production tax-invoice use.

No payment gateway existed in the input project. Payments are disabled by default. To enable **simulated payments only**, set server environment `ENABLE_TEST_PAYMENTS=true` and run as a database administrator:

```sql
UPDATE public.gs_settings SET test_payments_enabled = true WHERE id = true;
```

Restart/redeploy after environment changes. Open an unpaid invoice and choose **Start / resume test payment**. A persisted pending transaction is created; explicitly simulate success or failure. Interrupted attempts remain resumable after reload. Failed attempts can be retried. Unique indexes and idempotency keys prevent duplicate pending/paid records. Managers can simulate full refunds of paid test transactions. No real money moves. Test records are labelled in the UI/PDF and excluded from real-revenue summaries.

Production payments require a gateway adapter with server-created orders, verified signed webhooks, amount/currency checks, provider idempotency and server-only settlement/refund operations. Never reuse customer-controlled test-outcome endpoints for real settlement. Production gateway integration is not included or claimed.

## Vercel deployment

This upgraded edition runs frontend and API on **one origin** with HttpOnly cookies. Use **one Vercel project**, superseding the earlier separate-frontend/backend arrangement.

1. Upload extracted contents to GitHub, with `package.json`, `vercel.json`, `api/`, `server/`, `frontend/` and `swagger.yaml` at repository root. Exclude `.env` and `node_modules`.
2. Import into Vercel. Root Directory: repository root (`./`). Framework Preset: **Other**. The included configuration supplies static/function routing; do not override Output Directory to `frontend`.
3. Add `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_ORIGIN=https://your-project.vercel.app`, and `ALLOWED_ORIGINS` with that origin. Add optional payment/issuer variables above. Use Node.js 22 or 24.
4. Deploy, apply the migration separately in Supabase, and update Auth Site URL/redirect allowlist to the final domain. Visit `/api/health`, then `/login`.

Local and Vercel entry points share `server/app.js`. Production cookies are Secure/HttpOnly/SameSite=Lax. Tokens are not exposed to frontend JavaScript or stored in localStorage. Mutations require JSON/custom headers and permitted origins. Authenticated responses are private/no-store. Preview deployments need their own origin/redirect configuration for email registration.

The project was not published to your Vercel account during this task. `npm run dev:frontend` is an optional convenience running the same combined application on port 5173; adjust `APP_ORIGIN` when using it.

## Tests and verification limits

Run `npm test`. Tests execute the original schema and upgrade in PGlite with real RLS/SQL functions, checking ownership, blocked role escalation/direct writes, connector compatibility, meter bounds, tariff snapshots, invoice arithmetic, idempotent payments/refunds and capacity release. Tests use PGlite's native `gen_random_uuid()` and skip loading `pgcrypto` in that test environment only.

Chromium desktop/mobile integration checks passed for login, role redirects, cookie persistence, manager-route denial, vehicle creation, invoice PDF downloads, test payments, logout and responsive/reduced-motion rendering. They used mocked Supabase Auth and real PostgreSQL/RLS operations. The PDF was rendered and visually inspected. Actual Supabase Auth/email delivery and your Vercel deployment were not exercised because their account configuration/access was not supplied.

The editable demo has separate automated tests for registration/password validation, customer ownership, blocked role escalation, charging calculations, payment retries/refunds and persisted changes. A no-Supabase browser test completed registration/login, vehicle creation/editing, session request, admin start/meter/complete, substation editing, customer payment and demo PDF download, reload persistence and mobile layout. It confirmed zero real API calls during those demo workflows.

Main implementation files: `server/app.js`, `server/validation.js`, `server/invoice-pdf.js`, `sql/migrations/20261019_secure_workflows.sql`, `frontend/login.html`, `frontend/dashboard.html`, `frontend/workspace.js`, `frontend/workspace.css`, and `tests/workflows.test.cjs`.
