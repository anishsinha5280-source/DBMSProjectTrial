# Authenticated API reference

Base path: `/api`, on the same origin as the frontend. Sign in using the application to receive HttpOnly cookies. No user ID or role supplied by a customer determines ownership or authorization. PostgreSQL RLS also protects direct authenticated Supabase reads; validated RPCs are the only client-accessible mutation path.

All POST/PATCH/DELETE calls require `Content-Type: application/json` and `X-GridSync-Request: 1`. Use `{}` for actions without fields. IDs in URL paths must be positive integers. Dates use ISO 8601 with a timezone. Manager-only actions are checked both in Express and in SQL. Financial amounts are calculated by SQL, not accepted from the browser.

## Authentication

| Method / path | Payload / response |
| --- | --- |
| GET `/health` | Public configuration status and payment mode |
| POST `/auth/register` | `email`, `password` (12–128 chars), `full_name`; always customer; may require email confirmation |
| POST `/auth/login` | `email`, `password`; sets access/refresh cookies |
| POST `/auth/refresh` | `{}`; rotates cookies using refresh token |
| POST `/auth/logout` | `{}`; revokes current session and clears cookies |
| GET `/me` | Current protected profile |
| PATCH `/me` | `full_name`, optional `phone`; role/email/auth mapping cannot be edited |

All endpoints below require authentication. Customers read only their own vehicles, reservations, sessions, invoices and payment records. Managers read installation-wide operational data. Infrastructure/tariff lists and aggregate grid load are shared with signed-in users.

## Lists

GET `/vehicles`, `/reservations`, `/sessions`, `/invoices`, `/payments`, `/substations`, `/stations`, `/bays`, `/tariffs`, `/grid-load`. GET `/stations/:id/bays` lists station connectors. GET `/customers`, `/missions` and `/organizations` requires manager role.

Lists return JSON arrays. Invoice/session details are included in those records, subject to RLS. The frontend uses status/vehicle filters for session history. Archived vehicles remain in lists for historical references and are excluded from active vehicle selections.

## Vehicles

POST `/vehicles` and PATCH `/vehicles/:id` accept:

```json
{
  "license_plate": "KA-01-AB-1234",
  "make": "Tata",
  "model": "Nexon EV",
  "vehicle_type": "car",
  "connector_types": ["CCS2"],
  "battery_capacity_kwh": 40.5,
  "max_charge_rate_kw": 50
}
```

Supported connector values: `CCS2`, `Type2`, `CHAdeMO`, `NACS`. Registration must be 3–20 letters/digits/spaces/hyphens; its normalized value is unique per owner for active records. At least one connector is required. Capacity/power may be null when unknown. New vehicles always belong to the signed-in user. Managers may edit/archive existing operational vehicles but cannot reassign their ownership using these payloads.

DELETE `/vehicles/:id` with `{}` archives it. Edits/removal are blocked by relevant open sessions/bookings; scheduled fleet missions also block removal. History/invoice foreign keys remain intact.

## Reservations

POST `/reservations`: `vehicle_id`, `bay_id`, `start_time`, `end_time`. Ownership comes from the selected authorized vehicle. Times must be future, ordered and no more than 24 hours apart. Bay and vehicle overlaps and connector compatibility are checked inside the transaction.

POST `/reservations/:id/cancel`: `{}`. Requires ownership or manager access. Cancels associated queued/scheduled sessions, but refuses an active session.

## Charging sessions

POST `/sessions`: `vehicle_id`, `bay_id`, `meter_source` (`simulated` or `manual`), optional `scheduled_at`, optional `reservation_id`. A reservation must match the owner/vehicle/bay. Its window becomes the default scheduled start. No customer can supply tariffs, charges, allocation or payment state.

| Method / path | Role | Body |
| --- | --- | --- |
| POST `/sessions/:id/start` | Manager | `initial_meter_kwh` |
| POST `/sessions/:id/meter` | Manager | `final_meter_kwh`; also `simulation_elapsed_seconds` for simulated source |
| POST `/sessions/:id/complete` | Manager | Optional `idle_minutes`, default 0; readings must already be recorded |
| POST `/sessions/:id/fail` | Manager | `reason` (3+ characters); stops active charging; invoices delivered energy |
| POST `/sessions/:id/cancel` | Owner/manager | `reason` (3+ characters); only queued/scheduled |

Session transitions are `scheduled/queued → active → completed/failed`, or `scheduled/queued → cancelled`. Finalized records do not transition again. Meter values are kWh and allocated power is kW. Simulated duration is cumulative seconds. Manual duration uses server wall-clock time. Initial/final readings are normalized to three decimals. Tariff/financial snapshots are immutable through the exposed API.

## Infrastructure (manager mutations)

Use POST for creation and PATCH `/:id` for editing. Send the complete editable form fields:

| Resource | Required fields | Optional fields |
| --- | --- | --- |
| `/substations` | `name`, `code`, `max_grid_capacity_kw`, `base_load_kw`, `capacity_limit_pct`, `operational_status`, `load_source` | `location`, `region_code`, `constraints_note` |
| `/stations` | `substation_id`, `station_name`, `street_address`, `city`, `status`, `timezone` | — |
| `/bays` | `station_id`, `bay_number`, `plug_type`, `max_kw_output`, `is_operational` | — |
| `/tariffs` | `station_id`, `plan_name`, `start_hour`, `end_hour`, `base_rate_per_kwh`, `idle_fee_per_min`, `currency`, `tax_pct`, `service_fee`, `discount_amount`, `active` | — |

Substation status: `operational`, `maintenance`, `offline`. Baseline source: `estimated`, `manual`, `simulated`. Station status: `ACTIVE`, `MAINTENANCE`, `OFFLINE`. Booleans use JSON `true/false`. Currency is a three-letter uppercase code. Active tariff hour ranges cannot overlap. Station timezone must be an IANA timezone. Grid limits must support current allocations; active supplies cannot be taken offline through an edit. Session/booking constraints protect station/bay changes.

POST `/missions` (manager): `vehicle_id`, `fleet_org_id`, `mission_label`, `departure_time`, `target_soc_pct` (1–100), `priority_level` (positive integer). The vehicle must already belong to that fleet organization.

## Invoices and test transactions

Invoices are automatically generated at eligible session finalization. There is no client endpoint accepting an amount or inserting arbitrary invoices. GET `/invoices/:id/pdf` authorizes ownership/manager access and returns a generated `application/pdf` attachment. A legacy record without a verified snapshot returns 409.

| Method / path | Payload / behavior |
| --- | --- |
| POST `/invoices/:id/pay` | `idempotency_key`: UUID; creates/resumes pending test attempt |
| POST `/payments/:id/settle` | `outcome`: `paid` or `failed`; only test pending attempts; same outcome is idempotent |
| POST `/payments/:id/refund` | `{}`; manager only; full simulated refund of paid test attempt |

Both the server environment and database settings must enable test payments. No real gateway or real money collection/refund is implemented. Pending attempts survive reloads; only a single pending/paid attempt can exist per invoice. Failed attempts remain in history; retry with a new UUID. Test references begin with `SIM-`. Currency/amount are read from the invoice. Customer/vehicle/session associations follow immutable foreign keys through the invoice.

Errors return `{ "error": "explanation" }`, with 400 for invalid actions, 401 for sign-in/expiry, 403 for role/ownership denial, 409 for duplicate records/time slots, and 503 for missing Supabase configuration. Successful creates may return 201. Mutation results are the stored record. The frontend refreshes the relevant lists afterward.
