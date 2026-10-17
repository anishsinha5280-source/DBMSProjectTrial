# Entity-Relationship (ER) Diagram & Data Dictionary

## 1. Overview
This document provides the structural reference, Mermaid ER diagram, and complete data dictionary for the **Intelligent EV Charging Station and Fleet/Depot Management System**.

The database models the physical electrical hierarchy from upstream substations to charging stations and charger bays, while orchestrating commercial fleet missions, vehicle charging limits, reservations, active charging sessions, automated invoicing, payments, and hardware maintenance.

---

## 2. Mermaid Entity-Relationship Diagram

```mermaid
erDiagram
    SUBSTATION ||--o{ CHARGING_STATION : "supplies power to (1:N)"
    CHARGING_STATION ||--o{ CHARGER_BAY : "contains (1:N)"
    CHARGING_STATION ||--o{ TARIFF_PLAN : "defines (1:N)"

    FLEET_ORG ||--o{ APP_USER : "employs (1:N)"
    FLEET_ORG ||--o{ VEHICLE : "owns (1:N)"
    APP_USER ||--o{ VEHICLE : "operates / assigned to (1:N)"

    VEHICLE ||--o{ FLEET_MISSION : "dispatched on (1:N)"
    APP_USER ||--o{ FLEET_MISSION : "assigned driver (1:N)"

    CHARGER_BAY ||--o{ RESERVATION : "booked in (1:N)"
    VEHICLE ||--o{ RESERVATION : "reserved for (1:N)"
    APP_USER ||--o{ RESERVATION : "created by (1:N)"

    RESERVATION ||--o| CHARGING_SESSION : "initiates (1:0..1)"
    CHARGER_BAY ||--o{ CHARGING_SESSION : "hosts (1:N)"
    VEHICLE ||--o{ CHARGING_SESSION : "plugged into (1:N)"
    APP_USER ||--o{ CHARGING_SESSION : "conducted by (1:N)"

    CHARGER_BAY ||--o{ MAINTENANCE_LOG : "receives faults (1:N)"
    APP_USER ||--o{ MAINTENANCE_LOG : "repaired by technician (1:N)"

    CHARGING_SESSION ||--|| INVOICE : "bills to (1:1)"
    INVOICE ||--o{ PAYMENT : "settled by (1:N)"

    SUBSTATION {
        int substation_id PK "IDENTITY"
        varchar name "NOT NULL"
        decimal max_grid_capacity_kw "NOT NULL, > 0"
        varchar region_code "NOT NULL"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    CHARGING_STATION {
        int station_id PK "IDENTITY"
        int substation_id FK "NOT NULL -> Substation"
        varchar station_name "NOT NULL"
        varchar street_address "NOT NULL"
        varchar city "NOT NULL"
        varchar status "ACTIVE, INACTIVE, MAINTENANCE, OFFLINE"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    CHARGER_BAY {
        int bay_id PK "IDENTITY"
        int station_id FK "NOT NULL -> ChargingStation"
        int bay_number "NOT NULL, UNIQUE(station_id, bay_number)"
        varchar plug_type "CCS2, TYPE2, NACS"
        decimal max_kw_output "NOT NULL, > 0"
        bit is_operational "DEFAULT 1"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    TARIFF_PLAN {
        int tariff_id PK "IDENTITY"
        int station_id FK "NOT NULL -> ChargingStation"
        varchar plan_name "NOT NULL"
        int start_hour "0 to 23"
        int end_hour "0 to 23"
        decimal base_rate_per_kwh "NOT NULL, >= 0"
        decimal idle_fee_per_min "NOT NULL, >= 0"
        datetime2 created_at "DEFAULT SYSDATETIME"
    }

    FLEET_ORG {
        int org_id PK "IDENTITY"
        varchar company_name "NOT NULL"
        varchar tax_id UK "NOT NULL, UNIQUE"
        decimal credit_line_limit "NOT NULL, >= 0"
        decimal current_balance "NOT NULL, >= 0"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    APP_USER {
        int user_id PK "IDENTITY"
        int org_id FK "NULLABLE -> FleetOrg"
        varchar full_name "NOT NULL"
        varchar email UK "NOT NULL, UNIQUE"
        varchar phone "NOT NULL"
        varchar user_role "DRIVER, DEPOT_MANAGER, TECHNICIAN, ADMIN"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    VEHICLE {
        varchar vin PK "17-character VIN"
        int org_id FK "NOT NULL -> FleetOrg"
        int user_id FK "NOT NULL -> AppUser"
        varchar license_plate UK "NOT NULL, UNIQUE"
        decimal battery_capacity_kwh "NOT NULL, > 0"
        decimal max_charge_rate_kw "NOT NULL, > 0"
        decimal current_soc_pct "NOT NULL, 0.00 to 100.00"
        varchar ownership_type "FLEET, PRIVATE, LEASED"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    FLEET_MISSION {
        int mission_id PK "IDENTITY"
        varchar vin FK "NOT NULL -> Vehicle"
        int driver_id FK "NOT NULL -> AppUser"
        datetime2 departure_time "NOT NULL"
        decimal target_soc_pct "NOT NULL, 0.00 to 100.00"
        decimal route_distance_km "NOT NULL, >= 0"
        varchar mission_status "SCHEDULED, IN_PROGRESS, COMPLETED, CANCELLED"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    RESERVATION {
        int reservation_id PK "IDENTITY"
        int bay_id FK "NOT NULL -> ChargerBay"
        varchar vin FK "NOT NULL -> Vehicle"
        int user_id FK "NOT NULL -> AppUser"
        datetime2 start_time "NOT NULL"
        datetime2 end_time "NOT NULL, start_time < end_time"
        varchar reservation_status "PENDING, CONFIRMED, ACTIVE, COMPLETED, CANCELLED, NO_SHOW"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    CHARGING_SESSION {
        int session_id PK "IDENTITY"
        int bay_id FK "NOT NULL -> ChargerBay"
        varchar vin FK "NOT NULL -> Vehicle"
        int user_id FK "NOT NULL -> AppUser"
        int reservation_id FK "NOT NULL -> Reservation"
        datetime2 start_time "NOT NULL"
        datetime2 end_time "NULLABLE, start_time <= end_time"
        decimal allocated_kw "NOT NULL, > 0"
        decimal energy_delivered_kwh "NOT NULL, >= 0"
        int idle_minutes "NOT NULL, >= 0"
        varchar status "STARTED, CHARGING, COMPLETED, CANCELLED, FAULT"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    MAINTENANCE_LOG {
        int log_id PK "IDENTITY"
        int bay_id FK "NOT NULL -> ChargerBay"
        int technician_id FK "NOT NULL -> AppUser"
        varchar issue_reported "NOT NULL"
        datetime2 reported_at "DEFAULT SYSDATETIME"
        datetime2 resolved_at "NULLABLE, reported_at <= resolved_at"
        varchar repair_status "OPEN, IN_PROGRESS, RESOLVED, CANCELLED"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    INVOICE {
        int invoice_id PK "IDENTITY"
        int session_id FK "NOT NULL, UNIQUE -> ChargingSession"
        decimal energy_charge "NOT NULL, >= 0"
        decimal idle_penalty_charge "NOT NULL, >= 0"
        decimal tax_amount "NOT NULL, >= 0"
        decimal total_amount "COMPUTED PERSISTED"
        varchar status "PENDING, PAID, PARTIALLY_PAID, CANCELLED, OVERDUE"
        datetime2 created_at "DEFAULT SYSDATETIME"
        datetime2 updated_at "DEFAULT SYSDATETIME"
    }

    PAYMENT {
        int payment_id PK "IDENTITY"
        int invoice_id FK "NOT NULL -> Invoice"
        varchar payment_method "UPI, CARD, NET_BANKING, WALLET, CREDIT_LINE"
        decimal paid_amount "NOT NULL, > 0"
        varchar transaction_ref UK "NOT NULL, UNIQUE"
        datetime2 settled_at "DEFAULT SYSDATETIME"
        datetime2 created_at "DEFAULT SYSDATETIME"
    }
```

---

## 3. Detailed Data Dictionary

### 3.1 Substation
Supplies electrical high-voltage energy to downstream charging stations.
* **substation_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **name** (`VARCHAR(100)`, NOT NULL): Human-readable name of the utility substation.
* **max_grid_capacity_kw** (`DECIMAL(10,2)`, NOT NULL): Licensed peak transformer power limit in kilowatts. Checked by constraint `max_grid_capacity_kw > 0`.
* **region_code** (`VARCHAR(20)`, NOT NULL): Grid operator jurisdiction or distribution code.
* **created_at**, **updated_at** (`DATETIME2(7)`, NOT NULL): System audit timestamps.

### 3.2 ChargingStation
Physical depot or public charging plaza containing multiple charger bays.
* **station_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **substation_id** (`INT`, FK to `Substation`): Supplying grid substation.
* **station_name** (`VARCHAR(100)`, NOT NULL): Public or fleet facility identifier.
* **street_address** (`VARCHAR(255)`, NOT NULL): Physical address.
* **city** (`VARCHAR(100)`, NOT NULL): City location.
* **status** (`VARCHAR(20)`, NOT NULL): Station status constrained to `ACTIVE`, `INACTIVE`, `MAINTENANCE`, `OFFLINE`.

### 3.3 ChargerBay
Individual parking stall with a dedicated EVSE dispenser connector.
* **bay_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **station_id** (`INT`, FK to `ChargingStation`): Hosting charging station.
* **bay_number** (`INT`, NOT NULL): Bay number within the facility. Composite unique constraint `UQ_ChargerBay_Station_Bay (station_id, bay_number)`.
* **plug_type** (`VARCHAR(20)`, NOT NULL): Constrained to `CCS2`, `TYPE2`, `NACS`.
* **max_kw_output** (`DECIMAL(8,2)`, NOT NULL): Maximum DC or AC nameplate delivery rating (`> 0`).
* **is_operational** (`BIT`, NOT NULL, DEFAULT 1): Automatic hardware availability status (0 = under maintenance/fault, 1 = operational).

### 3.4 TariffPlan
Time-of-use pricing matrix defining energy rates and idle overstay penalties.
* **tariff_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **station_id** (`INT`, FK to `ChargingStation`): Facility to which this tariff applies.
* **plan_name** (`VARCHAR(50)`, NOT NULL): E.g., Daytime Peak, Night Off-Peak.
* **start_hour**, **end_hour** (`INT`, NOT NULL): Hours (0 to 23). Accommodates overnight wrapping (e.g., 22:00 to 06:00).
* **base_rate_per_kwh** (`DECIMAL(10,4)`, NOT NULL): Rate per kilowatt-hour.
* **idle_fee_per_min** (`DECIMAL(10,4)`, NOT NULL): Penalty per minute for post-charging bay occupancy.

### 3.5 FleetOrg
Commercial fleet enterprise, logistics carrier, or transit authority.
* **org_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **company_name** (`VARCHAR(150)`, NOT NULL): Legal business entity name.
* **tax_id** (`VARCHAR(50)`, UNIQUE, NOT NULL): Official tax or registration number.
* **credit_line_limit** (`DECIMAL(12,2)`, NOT NULL, DEFAULT 0.00): Maximum allowable credit for monthly charging settlement.
* **current_balance** (`DECIMAL(12,2)`, NOT NULL, DEFAULT 0.00): Outstanding unpaid credit line balance.

### 3.6 AppUser
Personnel and retail drivers interacting with the charging infrastructure.
* **user_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **org_id** (`INT`, FK to `FleetOrg`, NULLABLE): Enrolled fleet organization. NULL for retail drivers.
* **full_name** (`VARCHAR(100)`, NOT NULL): Driver or technician name.
* **email** (`VARCHAR(150)`, UNIQUE, NOT NULL): Account email address.
* **phone** (`VARCHAR(25)`, NOT NULL): Contact phone number.
* **user_role** (`VARCHAR(20)`, NOT NULL): Constrained to `DRIVER`, `DEPOT_MANAGER`, `TECHNICIAN`, `ADMIN`.

### 3.7 Vehicle
Electric vehicle registered for charging and fleet missions.
* **vin** (`VARCHAR(17)`, PK): Unique 17-character vehicle identification number.
* **org_id** (`INT`, FK to `FleetOrg`): Registered fleet organization or default enterprise sponsor.
* **user_id** (`INT`, FK to `AppUser`): Primary driver or operator.
* **license_plate** (`VARCHAR(20)`, UNIQUE, NOT NULL): State registration plate.
* **battery_capacity_kwh** (`DECIMAL(8,2)`, NOT NULL): Total battery pack capacity (`> 0`).
* **max_charge_rate_kw** (`DECIMAL(8,2)`, NOT NULL): Maximum DC fast charge ingestion limit (`> 0`).
* **current_soc_pct** (`DECIMAL(5,2)`, NOT NULL, DEFAULT 50.00): Current State-of-Charge percentage (0.00 to 100.00). *Design improvement.*
* **ownership_type** (`VARCHAR(20)`, NOT NULL): Constrained to `FLEET`, `PRIVATE`, `LEASED`.

### 3.8 FleetMission
Scheduled commercial route or transit dispatch with strict departure deadlines.
* **mission_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **vin** (`VARCHAR(17)`, FK to `Vehicle`): Dispatched vehicle.
* **driver_id** (`INT`, FK to `AppUser`): Assigned commercial driver.
* **departure_time** (`DATETIME2(7)`, NOT NULL): Target wheels-up timestamp.
* **target_soc_pct** (`DECIMAL(5,2)`, NOT NULL): Required battery SOC percentage before departure (0.00 to 100.00).
* **route_distance_km** (`DECIMAL(8,2)`, NOT NULL, DEFAULT 0.00): Projected route mileage.
* **mission_status** (`VARCHAR(20)`, NOT NULL): Constrained to `SCHEDULED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`.

### 3.9 Reservation
Time-window booking securing a specific bay for a vehicle.
* **reservation_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **bay_id** (`INT`, FK to `ChargerBay`): Reserved charging bay.
* **vin** (`VARCHAR(17)`, FK to `Vehicle`): Vehicle booked.
* **user_id** (`INT`, FK to `AppUser`): Booking user.
* **start_time**, **end_time** (`DATETIME2(7)`, NOT NULL): Reservation window (`start_time < end_time`). Enforced against overlapping intervals by trigger and serializable locks.
* **reservation_status** (`VARCHAR(20)`, NOT NULL): Constrained to `PENDING`, `CONFIRMED`, `ACTIVE`, `COMPLETED`, `CANCELLED`, `NO_SHOW`.

### 3.10 ChargingSession
Physical energy dispensing event linking reservation, charger bay, and vehicle.
* **session_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **bay_id** (`INT`, FK to `ChargerBay`): Hardware bay dispensing power.
* **vin** (`VARCHAR(17)`, FK to `Vehicle`): EV receiving power.
* **user_id** (`INT`, FK to `AppUser`): Operating user.
* **reservation_id** (`INT`, FK to `Reservation`): Originating reservation.
* **start_time** (`DATETIME2(7)`, NOT NULL): Session initiation timestamp.
* **end_time** (`DATETIME2(7)`, NULLABLE): Session termination timestamp (`start_time <= end_time`).
* **allocated_kw** (`DECIMAL(8,2)`, NOT NULL): Actively negotiated charging power draw. Must not breach bay rating, vehicle rating, or upstream substation headroom.
* **energy_delivered_kwh** (`DECIMAL(10,3)`, NOT NULL, DEFAULT 0.000): Metred electricity transferred.
* **idle_minutes** (`INT`, NOT NULL, DEFAULT 0): Post-charge vehicle dwell time.
* **status** (`VARCHAR(20)`, NOT NULL): Constrained to `STARTED`, `CHARGING`, `COMPLETED`, `CANCELLED`, `FAULT`.

### 3.11 MaintenanceLog
Tracks hardware anomalies, repair tickets, and technician interventions.
* **log_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **bay_id** (`INT`, FK to `ChargerBay`): Affected charger bay.
* **technician_id** (`INT`, FK to `AppUser`): Servicing technician.
* **issue_reported** (`VARCHAR(500)`, NOT NULL): Fault description.
* **reported_at** (`DATETIME2(7)`, NOT NULL, DEFAULT SYSDATETIME()).
* **resolved_at** (`DATETIME2(7)`, NULLABLE): Timestamp repair concluded.
* **repair_status** (`VARCHAR(20)`, NOT NULL): Constrained to `OPEN`, `IN_PROGRESS`, `RESOLVED`, `CANCELLED`. Open faults automatically mark `ChargerBay.is_operational = 0`.

### 3.12 Invoice
Financial invoice generated upon completion of a charging session.
* **invoice_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **session_id** (`INT`, FK to `ChargingSession`, UNIQUE): Exactly one invoice per charging session.
* **energy_charge** (`DECIMAL(10,2)`, NOT NULL): `energy_delivered_kwh * base_rate_per_kwh`.
* **idle_penalty_charge** (`DECIMAL(10,2)`, NOT NULL): `idle_minutes * idle_fee_per_min`.
* **tax_amount** (`DECIMAL(10,2)`, NOT NULL): Applicable statutory tax.
* **total_amount** (`DECIMAL(10,2)`, COMPUTED PERSISTED): `(energy_charge + idle_penalty_charge + tax_amount)`.
* **status** (`VARCHAR(20)`, NOT NULL): Constrained to `PENDING`, `PAID`, `PARTIALLY_PAID`, `CANCELLED`, `OVERDUE`.

### 3.13 Payment
Financial settlement transaction linked to an invoice.
* **payment_id** (`INT IDENTITY(1,1)`, PK): Unique surrogate identifier.
* **invoice_id** (`INT`, FK to `Invoice`): Associated invoice.
* **payment_method** (`VARCHAR(20)`, NOT NULL): Constrained to `UPI`, `CARD`, `NET_BANKING`, `WALLET`, `CREDIT_LINE`.
* **paid_amount** (`DECIMAL(10,2)`, NOT NULL): Currency amount paid (`> 0`).
* **transaction_ref** (`VARCHAR(100)`, UNIQUE, NOT NULL): Gateway or bank transaction reference.
* **settled_at** (`DATETIME2(7)`, NOT NULL, DEFAULT SYSDATETIME()).
