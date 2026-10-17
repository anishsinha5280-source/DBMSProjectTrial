<p align="center">
  <img src="https://img.shields.io/badge/PostgreSQL-16+-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Status-Active_Development-f59e0b?style=for-the-badge" />
</p>

# GridSync — Intelligent EV Charging & Depot Management Engine

> A database-driven orchestration engine that balances physical electrical grid capacity with the scheduling demands of commercial fleets and retail EV drivers — ensuring every delivery van hits its target state-of-charge before departure without tripping a single substation breaker.

---

## Table of Contents

- [Overview](#overview)
- [Key Capabilities](#key-capabilities)
- [Architecture](#architecture)
  - [System Flow](#system-flow)
  - [Entity-Relationship Model](#entity-relationship-model)
- [Database Schema](#database-schema)
  - [Grid Infrastructure Layer](#1-grid-infrastructure-layer)
  - [Station & Hardware Layer](#2-station--hardware-layer)
  - [Tariff & Pricing Layer](#3-tariff--pricing-layer)
  - [User & Fleet Layer](#4-user--fleet-layer)
  - [Vehicle & Mission Layer](#5-vehicle--mission-layer)
  - [Reservation & Session Layer](#6-reservation--session-layer)
  - [Billing & Payment Layer](#7-billing--payment-layer)
  - [Maintenance Layer](#8-maintenance-layer)
- [Constraint Enforcement](#constraint-enforcement)
- [Business Rules](#business-rules)
- [Getting Started](#getting-started)
- [Tech Stack](#tech-stack)
- [License](#license)

---

## Overview

GridSync is not just a charger-booking database — it is an **active arbiter** of electrical capacity, fleet logistics, and financial settlement. Traditional EV charging platforms treat chargers as passive power outlets. GridSync models the **upstream electrical hierarchy** from regional substations down to individual charger bays, enabling the system to:

- **Prevent transformer overloads** by tracking real-time substation headroom.
- **Prioritize mission-critical fleet charging** over casual retail top-ups during peak demand.
- **Enforce temporal exclusion** at the SQL level, making double-bookings physically impossible.
- **Automate hardware quarantine** — a logged fault immediately removes a bay from the booking pool.

The engine captures the complete lifecycle: from grid supply limits and dynamic hourly electricity rates, through reservation and energy delivery, to itemized invoicing and payment settlement.

---

## Key Capabilities

| Capability | Description |
|---|---|
| **Grid-Aware Scheduling** | Real-time substation capacity tracking prevents demand spikes and breaker trips |
| **Fleet Mission Priority** | Commercial vehicles with departure deadlines are prioritized over retail charging |
| **Temporal Exclusion Locks** | PostgreSQL `tsrange` exclusion constraints eliminate double-bookings at the engine level |
| **Dynamic Time-of-Use Pricing** | Tariff plans with hourly rate windows drive cost-optimal charge scheduling |
| **Auto-Quarantine on Fault** | Maintenance log entries automatically set `ChargerBay.is_operational = false` |
| **Itemized Billing** | Invoices reflect energy costs, idle-time penalties, and applicable tariff bands |
| **Multi-Role Access** | Drivers, depot managers, and technicians each operate within scoped permissions |

---

## Architecture

### System Flow

The data model flows from **grid infrastructure** down to **user demand** and **vehicle dispatch**, then across to **financial settlement** and **hardware maintenance**:

```
┌─────────────────────────────────────────────────────────────────┐
│                     GRID INFRASTRUCTURE                         │
│                                                                 │
│   Substation ──┬──► ChargingStation ──► ChargerBay              │
│   (capacity)   │    (location)          (plug type, kW rating)  │
│                │                                                │
│                └──► TariffPlan ──► Rate Windows (ToU pricing)   │
└────────────────────────────┬────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                              ▼
┌──────────────────────┐       ┌──────────────────────────┐
│    USER & FLEET      │       │   VEHICLE & MISSION      │
│                      │       │                          │
│  AppUser ──► Roles   │       │  Vehicle ──► FleetMission│
│  FleetOrg ──► Deps   │       │  (SoC, battery cap)     │
│                      │       │  (departure, target %)   │
└──────────┬───────────┘       └────────────┬─────────────┘
           │                                │
           └──────────┬─────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                  OPERATIONS & TRANSACTIONS                      │
│                                                                 │
│   Reservation ──► ChargingSession ──► Invoice ──► Payment      │
│   (tsrange        (kWh delivered,      (energy +    (gateway,   │
│    exclusion)      throttle vs          idle         status)    │
│                    headroom)            penalties)              │
│                                                                 │
│   MaintenanceLog ──► auto-quarantine ChargerBay                │
└─────────────────────────────────────────────────────────────────┘
```

### Entity-Relationship Model

```
Substation 1───* ChargingStation 1───* ChargerBay
                      │                    │
                      * TariffPlan         │
                                           │
AppUser *───1 FleetOrg                     │
   │                                       │
   * Vehicle *───* FleetMission            │
   │                                       │
   └──── Reservation 1───1 ChargerBay ─────┘
              │
              1 ChargingSession
              │
              1 Invoice 1───* Payment

ChargerBay 1───* MaintenanceLog
```

---

## Database Schema

### 1. Grid Infrastructure Layer

#### `Substation`

Represents a regional electrical substation that supplies power to one or more charging stations.

| Column | Type | Description |
|---|---|---|
| `substation_id` | `SERIAL PK` | Unique identifier |
| `name` | `VARCHAR(100)` | Substation designation |
| `region` | `VARCHAR(100)` | Geographic region |
| `max_capacity_kw` | `DECIMAL(10,2)` | Maximum supply capacity in kilowatts |
| `current_load_kw` | `DECIMAL(10,2)` | Real-time aggregate load |
| `status` | `VARCHAR(20)` | `active` · `maintenance` · `offline` |
| `commissioned_date` | `DATE` | Date the substation went live |

---

### 2. Station & Hardware Layer

#### `ChargingStation`

A physical location containing multiple charger bays, powered by a parent substation.

| Column | Type | Description |
|---|---|---|
| `station_id` | `SERIAL PK` | Unique identifier |
| `substation_id` | `INT FK` | Parent substation reference |
| `name` | `VARCHAR(150)` | Station name |
| `address` | `TEXT` | Street address |
| `latitude` | `DECIMAL(9,6)` | GPS latitude |
| `longitude` | `DECIMAL(9,6)` | GPS longitude |
| `total_bays` | `INT` | Number of charger bays on site |
| `is_active` | `BOOLEAN` | Whether the station is currently operational |

#### `ChargerBay`

An individual charging point within a station, defined by its connector type and power rating.

| Column | Type | Description |
|---|---|---|
| `bay_id` | `SERIAL PK` | Unique identifier |
| `station_id` | `INT FK` | Parent station reference |
| `bay_label` | `VARCHAR(20)` | Human-readable bay identifier (e.g., `A-03`) |
| `plug_type` | `VARCHAR(10)` | `CCS2` · `Type2` · `NACS` |
| `max_kw` | `DECIMAL(7,2)` | Maximum kilowatt output rating |
| `is_operational` | `BOOLEAN` | `false` when under maintenance (auto-set by triggers) |
| `installed_date` | `DATE` | Hardware installation date |

---

### 3. Tariff & Pricing Layer

#### `TariffPlan`

Defines time-of-use electricity rates that govern billing for sessions at a given station.

| Column | Type | Description |
|---|---|---|
| `tariff_id` | `SERIAL PK` | Unique identifier |
| `station_id` | `INT FK` | Station this tariff applies to |
| `plan_name` | `VARCHAR(100)` | Descriptive plan name |
| `rate_per_kwh` | `DECIMAL(6,4)` | Cost per kilowatt-hour (base rate) |
| `peak_rate_per_kwh` | `DECIMAL(6,4)` | Peak-hour rate per kWh |
| `off_peak_rate_per_kwh` | `DECIMAL(6,4)` | Off-peak rate per kWh |
| `idle_penalty_per_min` | `DECIMAL(5,2)` | Per-minute penalty for post-charge idle time |
| `peak_start` | `TIME` | Start of peak pricing window |
| `peak_end` | `TIME` | End of peak pricing window |
| `effective_from` | `DATE` | Plan effective start date |
| `effective_to` | `DATE` | Plan expiration date (nullable for open-ended) |

---

### 4. User & Fleet Layer

#### `AppUser`

Any authenticated user of the system — drivers, depot managers, or maintenance technicians.

| Column | Type | Description |
|---|---|---|
| `user_id` | `SERIAL PK` | Unique identifier |
| `fleet_org_id` | `INT FK` | Associated fleet organization (nullable for retail users) |
| `full_name` | `VARCHAR(100)` | User's full name |
| `email` | `VARCHAR(150) UNIQUE` | Login email |
| `phone` | `VARCHAR(20)` | Contact phone number |
| `role` | `VARCHAR(20)` | `driver` · `depot_manager` · `technician` |
| `is_active` | `BOOLEAN` | Account status |
| `created_at` | `TIMESTAMP` | Account creation timestamp |

#### `FleetOrg`

A commercial fleet organization that owns or operates multiple vehicles.

| Column | Type | Description |
|---|---|---|
| `fleet_org_id` | `SERIAL PK` | Unique identifier |
| `org_name` | `VARCHAR(150)` | Organization name |
| `billing_address` | `TEXT` | Billing address |
| `contact_email` | `VARCHAR(150)` | Primary contact email |
| `max_vehicles` | `INT` | Licensed vehicle capacity |
| `contract_type` | `VARCHAR(30)` | `prepaid` · `postpaid` · `enterprise` |
| `created_at` | `TIMESTAMP` | Registration timestamp |

---

### 5. Vehicle & Mission Layer

#### `Vehicle`

An electric vehicle registered in the system, linked to its owner/operator.

| Column | Type | Description |
|---|---|---|
| `vehicle_id` | `SERIAL PK` | Unique identifier |
| `user_id` | `INT FK` | Owner/operator |
| `fleet_org_id` | `INT FK` | Fleet association (nullable for personal vehicles) |
| `vin` | `VARCHAR(17) UNIQUE` | Vehicle Identification Number |
| `make` | `VARCHAR(50)` | Manufacturer |
| `model` | `VARCHAR(50)` | Model name |
| `year` | `INT` | Model year |
| `battery_capacity_kwh` | `DECIMAL(6,2)` | Total battery capacity |
| `current_soc_pct` | `DECIMAL(5,2)` | Current state-of-charge percentage |
| `plug_compatibility` | `VARCHAR(10)` | `CCS2` · `Type2` · `NACS` |

#### `FleetMission`

A scheduled commercial mission that establishes the departure deadline and required battery state.

| Column | Type | Description |
|---|---|---|
| `mission_id` | `SERIAL PK` | Unique identifier |
| `vehicle_id` | `INT FK` | Assigned vehicle |
| `fleet_org_id` | `INT FK` | Owning fleet organization |
| `mission_label` | `VARCHAR(100)` | Mission description (e.g., "AM Delivery Route — Zone 4") |
| `departure_time` | `TIMESTAMP` | Hard departure deadline |
| `target_soc_pct` | `DECIMAL(5,2)` | Required battery percentage at departure |
| `priority_level` | `INT` | Scheduling priority (1 = highest) |
| `status` | `VARCHAR(20)` | `scheduled` · `charging` · `ready` · `departed` |

---

### 6. Reservation & Session Layer

#### `Reservation`

A time-bound booking of a specific charger bay, protected by a temporal exclusion constraint.

| Column | Type | Description |
|---|---|---|
| `reservation_id` | `SERIAL PK` | Unique identifier |
| `user_id` | `INT FK` | Booking user |
| `vehicle_id` | `INT FK` | Vehicle to be charged |
| `bay_id` | `INT FK` | Reserved charger bay |
| `time_slot` | `TSRANGE` | Reserved time window (exclusion-constrained) |
| `status` | `VARCHAR(20)` | `confirmed` · `checked_in` · `completed` · `cancelled` |
| `created_at` | `TIMESTAMP` | Booking timestamp |

> **Constraint:** `EXCLUDE USING gist (bay_id WITH =, time_slot WITH &&)` — prevents overlapping reservations on the same bay at the SQL engine level.

#### `ChargingSession`

Records the physical act of charging once a reservation is fulfilled.

| Column | Type | Description |
|---|---|---|
| `session_id` | `SERIAL PK` | Unique identifier |
| `reservation_id` | `INT FK UNIQUE` | Originating reservation (1:1) |
| `bay_id` | `INT FK` | Charger bay used |
| `vehicle_id` | `INT FK` | Vehicle charged |
| `start_time` | `TIMESTAMP` | Plug-in timestamp |
| `end_time` | `TIMESTAMP` | Plug-out timestamp |
| `energy_delivered_kwh` | `DECIMAL(7,2)` | Total energy delivered |
| `avg_power_kw` | `DECIMAL(7,2)` | Average power draw |
| `peak_power_kw` | `DECIMAL(7,2)` | Peak instantaneous power draw |
| `idle_minutes` | `DECIMAL(6,2)` | Post-charge idle duration |
| `soc_start_pct` | `DECIMAL(5,2)` | Battery SoC at session start |
| `soc_end_pct` | `DECIMAL(5,2)` | Battery SoC at session end |
| `throttled` | `BOOLEAN` | Whether kW draw was throttled due to substation headroom |

---

### 7. Billing & Payment Layer

#### `Invoice`

An itemized bill generated upon session termination.

| Column | Type | Description |
|---|---|---|
| `invoice_id` | `SERIAL PK` | Unique identifier |
| `session_id` | `INT FK UNIQUE` | Associated charging session (1:1) |
| `user_id` | `INT FK` | Billed user |
| `energy_cost` | `DECIMAL(10,2)` | Charge for energy consumed (tariff-based) |
| `idle_penalty` | `DECIMAL(10,2)` | Charge for post-charge idle time |
| `total_amount` | `DECIMAL(10,2)` | `energy_cost + idle_penalty` |
| `currency` | `VARCHAR(3)` | ISO 4217 currency code |
| `issued_at` | `TIMESTAMP` | Invoice generation timestamp |
| `due_date` | `DATE` | Payment due date |
| `status` | `VARCHAR(20)` | `pending` · `paid` · `overdue` · `disputed` |

#### `Payment`

Records individual payment transactions against an invoice.

| Column | Type | Description |
|---|---|---|
| `payment_id` | `SERIAL PK` | Unique identifier |
| `invoice_id` | `INT FK` | Associated invoice |
| `amount` | `DECIMAL(10,2)` | Amount paid |
| `payment_method` | `VARCHAR(30)` | `credit_card` · `fleet_account` · `wallet` |
| `gateway_ref` | `VARCHAR(100)` | Payment gateway transaction reference |
| `status` | `VARCHAR(20)` | `success` · `failed` · `refunded` |
| `paid_at` | `TIMESTAMP` | Payment timestamp |

---

### 8. Maintenance Layer

#### `MaintenanceLog`

Tracks hardware faults and service events for charger bays. Logging a fault automatically quarantines the bay.

| Column | Type | Description |
|---|---|---|
| `log_id` | `SERIAL PK` | Unique identifier |
| `bay_id` | `INT FK` | Affected charger bay |
| `reported_by` | `INT FK` | Reporting user (typically a technician) |
| `fault_type` | `VARCHAR(50)` | `hardware` · `software` · `electrical` · `connector` |
| `description` | `TEXT` | Detailed fault description |
| `severity` | `VARCHAR(10)` | `low` · `medium` · `high` · `critical` |
| `reported_at` | `TIMESTAMP` | Fault report timestamp |
| `resolved_at` | `TIMESTAMP` | Resolution timestamp (nullable if unresolved) |
| `resolution_notes` | `TEXT` | Technician's resolution notes |

> **Trigger:** On `INSERT` into `MaintenanceLog`, a database trigger sets `ChargerBay.is_operational = false` for the affected bay. On resolution (`resolved_at IS NOT NULL`), the trigger restores `is_operational = true`.

---

## Constraint Enforcement

The database enforces critical business invariants at the engine level — not in application code:

| Constraint | Mechanism | Purpose |
|---|---|---|
| No double-booking | `EXCLUDE USING gist` on `(bay_id, time_slot)` | Physically impossible overlapping reservations |
| Substation overload prevention | `CHECK (current_load_kw <= max_capacity_kw)` | Prevents load from exceeding grid capacity |
| Session-to-reservation integrity | `UNIQUE` on `ChargingSession.reservation_id` | Guarantees 1:1 session-per-reservation |
| Auto-quarantine on fault | `TRIGGER` on `MaintenanceLog` | Immediately removes faulted bays from booking pool |
| Plug compatibility | Application-level `CHECK` | Vehicles can only book bays with matching plug types |
| Invoice total consistency | `CHECK (total_amount = energy_cost + idle_penalty)` | Ensures billing arithmetic integrity |

---

## Business Rules

1. **Fleet Priority Scheduling** — When substation headroom is constrained, vehicles with active `FleetMission` records (sorted by `priority_level` ASC and `departure_time` ASC) are allocated power before retail users.

2. **Dynamic Throttling** — If `Substation.current_load_kw` approaches `max_capacity_kw`, active sessions are throttled (reducing `avg_power_kw`) to maintain grid stability. The `ChargingSession.throttled` flag records this event.

3. **Idle Penalty Enforcement** — Once a vehicle reaches its target SoC (or 100%), any time the vehicle remains plugged in accrues idle minutes billed at `TariffPlan.idle_penalty_per_min`.

4. **Maintenance Quarantine** — A `MaintenanceLog` entry with `severity = 'critical'` or `'high'` immediately sets the bay offline. Existing reservations on the affected bay are flagged for rebooking.

5. **Time-of-Use Optimization** — The scheduling engine prefers off-peak tariff windows for non-urgent charging, reducing fleet operating costs by shifting demand to cheaper rate bands.

---

## Getting Started

### Prerequisites

- **PostgreSQL 16+** (required for `tsrange` and GiST exclusion constraints)
- **btree_gist extension** (must be enabled for exclusion constraints)

### Setup

```bash
# 1. Clone the repository
git clone https://github.com/your-org/gridsync.git
cd gridsync

# 2. Create the database
createdb gridsync

# 3. Enable required extensions
psql -d gridsync -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"

# 4. Run the schema migration
psql -d gridsync -f schema/001_create_tables.sql

# 5. Seed sample data (optional)
psql -d gridsync -f schema/002_seed_data.sql

# 6. Apply triggers and functions
psql -d gridsync -f schema/003_triggers.sql
```

### Verify Installation

```bash
psql -d gridsync -c "\dt"
```

You should see all 11 tables listed: `substation`, `charging_station`, `charger_bay`, `tariff_plan`, `app_user`, `fleet_org`, `vehicle`, `fleet_mission`, `reservation`, `charging_session`, `invoice`, `payment`, `maintenance_log`.

---

## Tech Stack

| Component | Technology |
|---|---|
| **Database Engine** | PostgreSQL 16+ |
| **Temporal Constraints** | `tsrange` + GiST exclusion indexes |
| **Automated Triggers** | PL/pgSQL |
| **Extension** | `btree_gist` |

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <em>Built to keep the grid stable, the fleet charged, and the books balanced.</em>
</p>
