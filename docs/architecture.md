# System Architecture & Technical Specifications

## 1. Architectural Overview
The **Intelligent EV Charging Station and Fleet/Depot Management System** is architected as an enterprise-grade, high-concurrency relational database operating on Microsoft SQL Server. The engine harmonizes three intersecting operational vectors:
1. **Physical Energy Infrastructure**: Upstream medium/high-voltage utility substations feeding distributed charging plazas, each containing multiple high-output charger bays.
2. **Commercial Fleet Logistics**: Enterprise fleet operators managing high-utilization commercial vehicles with strict mission departure schedules, route distances, and minimum battery State-of-Charge (SOC) requirements.
3. **Financial & Operational Lifecycle**: Automated reservation scheduling, dynamic tariff resolution, real-time energy metering, penalty fees, multi-channel payment reconciliation, and automated maintenance tracking.

---

## 2. High-Level System Topology

```
+-------------------------------------------------------------+
|                      UTILITY SUBSTATION                     |
|           (Upstream Grid Capacity: 1,200 - 3,000 kW)        |
+-------------------------------------------------------------+
                              |
              +---------------+---------------+
              |                               |
              v                               v
+---------------------------+   +---------------------------+
|     CHARGING STATION 1    |   |     CHARGING STATION 2    |
|   (Central Fleet Depot)   |   | (Downtown Commercial Hub) |
+---------------------------+   +---------------------------+
              |                               |
    +---------+---------+           +---------+---------+
    |         |         |           |         |         |
    v         v         v           v         v         v
+-------+ +-------+ +-------+   +-------+ +-------+ +-------+
| Bay 1 | | Bay 2 | | Bay 3 |   | Bay 4 | | Bay 5 | | Bay 6 |
| CCS2  | | CCS2  | | NACS  |   | CCS2  | | TYPE2 | | NACS  |
+-------+ +-------+ +-------+   +-------+ +-------+ +-------+
    |
    v
+-------------------------------------------------------------+
|               TRANSACTIONAL ENGINE (SQL SERVER)             |
|                                                             |
|  * Reservation Engine (Concurrency-Safe UPDLOCK/HOLDLOCK)    |
|  * Smart Grid Balancing (Substation Transformer Protection) |
|  * Fleet Mission Prioritization Engine                      |
|  * Automated Billing, Tariff Engine & Invoicing Pipeline    |
|  * Maintenance Synchronization Trigger                      |
+-------------------------------------------------------------+
```

---

## 3. Concurrency, Isolation, & Locking Strategy

### 3.1 Addressing the Absence of PostgreSQL `tsrange` / `GIST`
In PostgreSQL, temporal non-overlap constraints are conventionally declared using exclusion constraints:
```sql
-- PostgreSQL syntax (NOT supported in SQL Server):
EXCLUDE USING GIST (bay_id WITH =, tsrange(start_time, end_time) WITH &&);
```
Microsoft SQL Server does not have a native temporal range data type (`tsrange`) or generalized GiST index exclusion syntax. To achieve equal or superior transactional guarantees in SQL Server without race conditions, this system employs a **defense-in-depth, two-tier concurrency architecture**:

#### Tier 1: Stored Procedure Serialization (`sp_CreateReservation`)
When creating a reservation, the stored procedure initiates a local transaction and applies explicit locking hints:
```sql
SELECT 1 
FROM dbo.Reservation WITH (UPDLOCK, HOLDLOCK)
WHERE bay_id = @p_bay_id
  AND reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
  AND start_time < @p_end_time
  AND end_time > @p_start_time;
```
* `UPDLOCK`: Places update locks rather than shared locks, preventing deadlocks when two concurrent connections read the same time slot and both subsequently attempt to insert.
* `HOLDLOCK`: Equivalent to `SERIALIZABLE`, holding range/intent locks until the transaction completes, preventing phantom insertions between the check and the `INSERT`.

#### Tier 2: Relational Fail-Safe Trigger (`trg_Reservation_ValidateAndPreventOverlap`)
If any external client, ORM, or administrator bypasses the stored procedure and issues a direct `INSERT` or `UPDATE`, the trigger evaluates the full batch in the `inserted` virtual table:
```sql
IF EXISTS (
    SELECT 1
    FROM inserted i
    INNER JOIN dbo.Reservation r 
        ON i.bay_id = r.bay_id 
       AND i.reservation_id <> r.reservation_id
    WHERE i.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
      AND r.reservation_status IN ('PENDING', 'CONFIRMED', 'ACTIVE')
      AND r.start_time < i.end_time 
      AND r.end_time > i.start_time
)
BEGIN
    THROW 50002, 'Double booking rejected: The requested charger bay is already reserved during the specified time interval.', 1;
END
```

---

## 4. Smart Charging & Grid Capacity Protection

Substation overloading risks transformer trips, equipment degradation, and utility penalties. The database enforces substation capacity as a hard transactional invariant.

### 4.1 Headroom Formulation
For any substation $S$ at timestamp $T$:
$$\text{Allocated Load}(S) = \sum_{c \in \text{Sessions}(S, \text{Active})} \text{allocated\_kw}(c)$$
$$\text{Available Headroom}(S) = \text{max\_grid\_capacity\_kw}(S) - \text{Allocated Load}(S)$$

When a session requests power $P_{\text{req}}$:
$$P_{\text{req}} \le \min\Big(\text{ChargerBay.max\_kw\_output}, \; \text{Vehicle.max\_charge\_rate\_kw}, \; \text{Available Headroom}(S)\Big)$$

### 4.2 Eliminating Grid Headroom Race Conditions
If two vehicles plug in simultaneously at two different stations supplied by the same substation, both could read the available headroom before either commits, resulting in a collective power draw exceeding the substation rating.

To prevent this:
In `sp_StartChargingSession`, an `UPDLOCK, HOLDLOCK` is placed on the parent `Substation` record:
```sql
SELECT 
    @substation_id = sub.substation_id,
    @max_grid_capacity = sub.max_grid_capacity_kw
FROM dbo.ChargingStation cs
INNER JOIN dbo.Substation sub WITH (UPDLOCK, HOLDLOCK) 
    ON cs.substation_id = sub.substation_id
WHERE cs.station_id = @station_id;
```
This serializes concurrent power allocations on that specific substation without blocking sessions on other unrelated substations.

---

## 5. Intelligent Fleet Prioritization Algorithm

During peak hours or local grid curtailments, available charging power must be prioritized for commercial fleet operations with impending route deadlines.

### 5.1 Deterministic Urgency Formula
The system implements a deterministic, fully explainable scoring algorithm within `vw_ChargingPriority` and `sp_GetChargingPriority`:

$$\text{Priority Score} = W_{\text{org}} + W_{\text{deficit}} + W_{\text{time}}$$

Where:
* **Organizational Weight ($W_{\text{org}}$)**:
  * Commercial Fleet Vehicle: **+50.0**
  * Retail / Private Vehicle: **+10.0**
* **SOC Deficit Weight ($W_{\text{deficit}}$)**:
  $$W_{\text{deficit}} = \max\Big(0, \; (\text{target\_soc\_pct} - \text{current\_soc\_pct})\Big) \times 0.5$$
* **Departure Urgency Weight ($W_{\text{time}}$)**:
  $$W_{\text{time}} = \begin{cases}
  100.0 & \text{if } \Delta t \le 0 \text{ minutes (Overdue / Immediate)} \\
  80.0  & \text{if } 0 < \Delta t \le 60 \text{ minutes} \\
  50.0  & \text{if } 60 < \Delta t \le 180 \text{ minutes} \\
  30.0  & \text{if } 180 < \Delta t \le 360 \text{ minutes} \\
  10.0  & \text{if } \Delta t > 360 \text{ minutes}
  \end{cases}$$

This ensures that delivery vans and transit buses facing urgent departures jump to the top of the charging queue while casual drivers are gracefully queued.

---

## 6. Financial Settlement & Persisted Computations

To eliminate financial discrepancies and floating-point drift:
* All financial currencies and electrical rates are stored as exact numeric types: `DECIMAL(10,2)` or `DECIMAL(10,4)`.
* `total_amount` in `Invoice` is modeled as a **deterministic, persisted computed column**:
  ```sql
  total_amount AS (energy_charge + idle_penalty_charge + tax_amount) PERSISTED
  ```
  This guarantees that invoice totals are always indexable and impossible to desynchronize from line items.
* Payments update the invoice status via `trg_Payment_SyncInvoiceStatus`, supporting partial payments, full settlements, and enterprise credit lines seamlessly.

---

## 7. Indexing Architecture & Access Path Optimization

1. **Foreign Key Performance**: Every foreign key is covered by a non-clustered index, eliminating table scans during cascade checks, relational joins, and parent-child navigation.
2. **Temporal Overlap Optimization**:
   * `IX_Reservation_Bay_TimeRange (bay_id, start_time, end_time) INCLUDE (reservation_status, vin, user_id)` allows range-seek lookups in $O(\log N)$ time.
   * `IX_Reservation_ActiveOnly` provides a **filtered index** containing exclusively `PENDING`, `CONFIRMED`, and `ACTIVE` reservations, drastically reducing index size and page I/O.
3. **Grid Capacity Acceleration**:
   * `IX_ChargingSession_ActiveGridLoad (bay_id, allocated_kw) INCLUDE (vin, status) WHERE status IN ('STARTED', 'CHARGING')` ensures that calculating the current load of a substation touches only active, charging rows.
4. **Maintenance Health Lookups**:
   * `IX_MaintenanceLog_UnresolvedFaults` provides a filtered index on `('OPEN', 'IN_PROGRESS')` for instantaneous bay availability checks.
