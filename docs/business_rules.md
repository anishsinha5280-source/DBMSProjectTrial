# Business Rules & System Invariants

## 1. Upstream Electrical Hierarchy & Power Distribution
1. **Single Upstream Source**: Every `ChargingStation` is physically wired to and supplied by exactly one upstream utility `Substation`.
2. **Substation Multi-Station Supply**: A single `Substation` supplies electrical power to one or more `ChargingStation` facilities across a defined regional jurisdiction (`region_code`).
3. **Substation Capacity Limit**: `max_grid_capacity_kw` represents the physical transformer capacity and distribution license rating. It must be strictly greater than zero (`CK_Substation_MaxCapacity`).
4. **Hierarchical Bay Organization**: Every `ChargerBay` belongs to exactly one `ChargingStation`. A `ChargingStation` contains multiple `ChargerBay` units.
5. **Local Bay Numbering**: Within any given `ChargingStation`, `bay_number` must be unique (`UQ_ChargerBay_Station_Bay`).

---

## 2. Charger Bay Hardware & Status Constraints
1. **Supported EV Connector Standards**: Every charger bay must provide one of three recognized physical connector standards: `CCS2` (Combined Charging System 2), `TYPE2` (Mennekes AC), or `NACS` (North American Charging Standard) (`CK_ChargerBay_PlugType`).
2. **Hardware Delivery Rating**: `max_kw_output` must be strictly positive (`CK_ChargerBay_MaxKw`).
3. **Operational Availability Flag**: `is_operational` defaults to 1. When set to 0 (e.g. during an active maintenance fault), the bay cannot accept new reservations or initiate active charging sessions.
4. **Station Operational Lifecycle**: A station must have status `ACTIVE` for its bays to be bookable. If the station is `INACTIVE`, `MAINTENANCE`, or `OFFLINE`, reservations and charging are disallowed.

---

## 3. Dynamic Tariff Scheduling & Overnight Periods
1. **Time-of-Use Window**: Each station may define multiple tariff plans (`TariffPlan`) with `start_hour` and `end_hour` between 0 and 23.
2. **Standard Daytime Intervals**: Where `start_hour < end_hour`, the tariff applies continuously from `start_hour:00` up to `end_hour:00` (e.g., 06:00 to 22:00).
3. **Overnight Wrapping Intervals**: Where `start_hour > end_hour`, the tariff wraps past midnight (e.g., `start_hour = 22` and `end_hour = 6` signifies 22:00 to 06:00 overnight off-peak). In SQL queries and procedures, this is evaluated as:
   `((start_hour <= end_hour AND @hour >= start_hour AND @hour < end_hour) OR (start_hour > end_hour AND (@hour >= start_hour OR @hour < end_hour)))`
4. **Non-Negative Rates**: `base_rate_per_kwh >= 0.0000` and `idle_fee_per_min >= 0.0000`.

---

## 4. Multi-Tenant Fleet Organizations & Credit Management
1. **Enterprise Multi-Tenancy**: A `FleetOrg` can own multiple vehicles and employ multiple app users (`DRIVER`, `DEPOT_MANAGER`).
2. **Tax ID Uniqueness**: Each organization must possess a unique legal `tax_id` (`UQ_FleetOrg_TaxId`).
3. **Credit Line Control**: Organizations are granted a revolving `credit_line_limit >= 0.00`. The cumulative unsettled balance `current_balance >= 0.00` cannot exceed `credit_line_limit`.
4. **Credit Line Payment Validation**: Payments using method `CREDIT_LINE` verify that `current_balance + paid_amount <= credit_line_limit` before being authorized, automatically updating the organization's current balance.

---

## 5. Vehicle Specifications & State-of-Charge Dynamics
1. **Unique Identity**: Vehicles are uniquely keyed by their standard 17-character `vin` (Primary Key), and each vehicle must have a unique `license_plate` (`UQ_Vehicle_LicensePlate`).
2. **Battery & Ingestion Limits**: `battery_capacity_kwh > 0.00` and `max_charge_rate_kw > 0.00`.
3. **State-of-Charge (SOC)**: `current_soc_pct` is tracked as a percentage between `0.00` and `100.00`.
4. **SOC Updating**: Upon completion of a charging session, vehicle `current_soc_pct` is automatically incremented in proportion to the metered energy delivered:
   `new_soc = MIN(100.00, current_soc + (energy_delivered_kwh / battery_capacity_kwh) * 100.00)`.
5. **Ownership Types**: Validated by `CK_Vehicle_OwnershipType` as `FLEET`, `PRIVATE`, or `LEASED`.

---

## 6. Commercial Fleet Mission Scheduling & Priority Urgency Engine
1. **Mission Dispatch**: Represents commercial delivery routes or transit schedules with a mandatory `departure_time` and `target_soc_pct` (0.00 to 100.00).
2. **Deterministic Priority Scoring**: When grid capacity or bay availability is constrained, vehicles are scheduled via a deterministic scoring engine:
   $$\text{Urgency Score} = \text{Fleet Bonus} + \text{SOC Deficit Weight} + \text{Departure Urgency}$$
   * **Fleet Bonus**: `FLEET` ownership vehicles receive **50.0 points** (commercial delivery SLAs); retail vehicles receive **10.0 points**.
   * **SOC Deficit Weight**: $(\text{target\_soc\_pct} - \text{current\_soc\_pct}) \times 0.5$ points.
   * **Departure Urgency**:
     * Overdue or $\le 0$ minutes until departure: **100.0 points**
     * $\le 60$ minutes until departure: **80.0 points**
     * $\le 180$ minutes until departure: **50.0 points**
     * $\le 360$ minutes until departure: **30.0 points**
     * $> 360$ minutes: **10.0 points**
3. **Dynamic Priority Queue**: View `vw_ChargingPriority` and procedure `sp_GetChargingPriority` evaluate this score in real time and assign a `DENSE_RANK()`.

---

## 7. Concurrency-Safe Reservation Engine & Collision Prevention
1. **Strict Temporal Ordering**: `start_time < end_time` (`CK_Reservation_TimeInterval`).
2. **Bay Collision Prevention**: No two active reservations (`PENDING`, `CONFIRMED`, `ACTIVE`) for the same `bay_id` may overlap. The intersection condition is:
   `existing.start_time < new.end_time AND existing.end_time > new.start_time`
3. **Vehicle Collision Prevention**: The same `vin` cannot hold active reservations on two distinct bays with overlapping intervals.
4. **Hardware Operational Guard**: A reservation cannot be created on a bay whose `is_operational = 0`.
5. **SQL Server Serialization**: Because SQL Server does not have PostgreSQL's `tsrange` exclusion constraints, atomicity is guaranteed at two distinct layers:
   * **Stored Procedure**: `sp_CreateReservation` uses `UPDLOCK, HOLDLOCK` to serialize concurrent requests on the same bay.
   * **Trigger**: `trg_Reservation_ValidateAndPreventOverlap` acts as a fail-safe against direct `INSERT` or `UPDATE` statements, throwing error 50002.

---

## 8. Smart Grid Headroom & Substation Load Management
1. **Substation Headroom Invariant**: Total active power draw across all charging stations connected to a substation must never exceed `Substation.max_grid_capacity_kw`:
   $$\sum \text{allocated\_kw}_{\text{active}} \le \text{Substation.max\_grid\_capacity\_kw}$$
2. **Hardware Capacity Boundaries**: A session's `allocated_kw` must strictly satisfy:
   * $\text{allocated\_kw} \le \text{ChargerBay.max\_kw\_output}$
   * $\text{allocated\_kw} \le \text{Vehicle.max\_charge\_rate\_kw}$
   * $\text{allocated\_kw} \le (\text{Substation.max\_grid\_capacity\_kw} - \text{Current Substation Load})$
3. **Serialization Strategy**: In `sp_StartChargingSession`, an `UPDLOCK, HOLDLOCK` lock is acquired on the `Substation` record, preventing race conditions where two simultaneous sessions on different stations might both read available headroom and simultaneously overload the transformer.
4. **Enforcement Trigger**: `trg_ChargingSession_EnforceGridCapacity` performs validation on direct table modifications.

---

## 9. Automated Hardware Maintenance & Bay Availability
1. **Maintenance Logging**: Maintenance tickets (`MaintenanceLog`) are filed by certified personnel (`TECHNICIAN`, `DEPOT_MANAGER`, `ADMIN`).
2. **Automatic Offline Deactivation**: When a fault is created or updated with `repair_status IN ('OPEN', 'IN_PROGRESS')`, trigger `trg_MaintenanceLog_BayStatusSync` automatically sets `ChargerBay.is_operational = 0`.
3. **Automatic Online Reactivation**: When a fault is updated to `RESOLVED` (or `CANCELLED`), the trigger inspects whether any remaining `OPEN` or `IN_PROGRESS` faults exist for that bay. If zero unresolved faults remain, `ChargerBay.is_operational` is restored to `1`.
4. **Resolution Timestamp Integrity**: `resolved_at` must be `NULL` while open, and must be $\ge$ `reported_at` once resolved (`CK_MaintenanceLog_TimeInterval`).

---

## 10. Automated Billing, Invoicing, & Persisted Computations
1. **Session Completion Pipeline**: When `sp_CompleteChargingSession` executes:
   * Resolves applicable time-of-use tariff rate from `TariffPlan`.
   * Calculates energy charge: $\text{energy\_delivered\_kwh} \times \text{base\_rate\_per\_kwh}$.
   * Calculates idle penalty charge: $\text{idle\_minutes} \times \text{idle\_fee\_per\_min}$.
   * Calculates tax amount: $(\text{energy\_charge} + \text{idle\_penalty\_charge}) \times 18\%$.
   * Creates 1-to-1 `Invoice` record.
   * Atomically transitions `ChargingSession.status = 'COMPLETED'` and `Reservation.reservation_status = 'COMPLETED'`.
2. **Persisted Computed Column**: `Invoice.total_amount` is defined as:
   `AS (energy_charge + idle_penalty_charge + tax_amount) PERSISTED`
   This eliminates rounding discrepancies and guarantees mathematical determinism without requiring custom triggers.

---

## 11. Payment Processing & Invoice State Synchronization
1. **Supported Settlement Channels**: Constrained to `UPI`, `CARD`, `NET_BANKING`, `WALLET`, and `CREDIT_LINE` (`CK_Payment_PaymentMethod`).
2. **Split & Partial Payments**: An invoice may be settled through multiple incremental payments.
3. **Automated State Transition Machine**: Maintained via `trg_Payment_SyncInvoiceStatus`:
   * $\sum \text{paid\_amount} \ge \text{total\_amount} \implies \text{status} = \text{'PAID'}$
   * $0 < \sum \text{paid\_amount} < \text{total\_amount} \implies \text{status} = \text{'PARTIALLY\_PAID'}$
   * $\sum \text{paid\_amount} = 0 \implies \text{status} = \text{'PENDING'}$
4. **Audit Immutability**: Payments require unique external transaction references (`transaction_ref`).
