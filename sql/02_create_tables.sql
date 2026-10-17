-- ============================================================================
-- SCRIPT: 02_create_tables.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Creates the 13 core entities with appropriate SQL Server data types,
--              IDENTITY primary keys, NOT NULL specifications, defaults, and
--              persisted computed columns.
-- ============================================================================

USE EVChargingDB;
GO

-- 1. Substation
IF OBJECT_ID(N'dbo.Substation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Substation (
        substation_id           INT IDENTITY(1,1) NOT NULL,
        name                    VARCHAR(100)      NOT NULL,
        max_grid_capacity_kw    DECIMAL(10,2)     NOT NULL,
        region_code             VARCHAR(20)       NOT NULL,
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Substation_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Substation_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_Substation PRIMARY KEY CLUSTERED (substation_id)
    );
    PRINT 'Table Substation created.';
END
GO

-- 2. ChargingStation
IF OBJECT_ID(N'dbo.ChargingStation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ChargingStation (
        station_id              INT IDENTITY(1,1) NOT NULL,
        substation_id           INT               NOT NULL,
        station_name            VARCHAR(100)      NOT NULL,
        street_address          VARCHAR(255)      NOT NULL,
        city                    VARCHAR(100)      NOT NULL,
        status                  VARCHAR(20)       NOT NULL CONSTRAINT DF_ChargingStation_Status DEFAULT 'ACTIVE',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingStation_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingStation_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_ChargingStation PRIMARY KEY CLUSTERED (station_id)
    );
    PRINT 'Table ChargingStation created.';
END
GO

-- 3. ChargerBay
IF OBJECT_ID(N'dbo.ChargerBay', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ChargerBay (
        bay_id                  INT IDENTITY(1,1) NOT NULL,
        station_id              INT               NOT NULL,
        bay_number              INT               NOT NULL,
        plug_type               VARCHAR(20)       NOT NULL,
        max_kw_output           DECIMAL(8,2)      NOT NULL,
        is_operational          BIT               NOT NULL CONSTRAINT DF_ChargerBay_IsOperational DEFAULT 1,
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargerBay_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargerBay_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_ChargerBay PRIMARY KEY CLUSTERED (bay_id)
    );
    PRINT 'Table ChargerBay created.';
END
GO

-- 4. TariffPlan
IF OBJECT_ID(N'dbo.TariffPlan', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TariffPlan (
        tariff_id               INT IDENTITY(1,1) NOT NULL,
        station_id              INT               NOT NULL,
        plan_name               VARCHAR(50)       NOT NULL,
        start_hour              INT               NOT NULL,
        end_hour                INT               NOT NULL,
        base_rate_per_kwh       DECIMAL(10,4)     NOT NULL,
        idle_fee_per_min        DECIMAL(10,4)     NOT NULL CONSTRAINT DF_TariffPlan_IdleFee DEFAULT 0.0000,
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_TariffPlan_CreatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_TariffPlan PRIMARY KEY CLUSTERED (tariff_id)
    );
    PRINT 'Table TariffPlan created.';
END
GO

-- 5. FleetOrg
IF OBJECT_ID(N'dbo.FleetOrg', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FleetOrg (
        org_id                  INT IDENTITY(1,1) NOT NULL,
        company_name            VARCHAR(150)      NOT NULL,
        tax_id                  VARCHAR(50)       NOT NULL,
        credit_line_limit       DECIMAL(12,2)     NOT NULL CONSTRAINT DF_FleetOrg_CreditLimit DEFAULT 0.00,
        current_balance         DECIMAL(12,2)     NOT NULL CONSTRAINT DF_FleetOrg_CurrentBalance DEFAULT 0.00,
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetOrg_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetOrg_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_FleetOrg PRIMARY KEY CLUSTERED (org_id)
    );
    PRINT 'Table FleetOrg created.';
END
GO

-- 6. AppUser
IF OBJECT_ID(N'dbo.AppUser', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppUser (
        user_id                 INT IDENTITY(1,1) NOT NULL,
        org_id                  INT               NULL,
        full_name               VARCHAR(100)      NOT NULL,
        email                   VARCHAR(150)      NOT NULL,
        phone                   VARCHAR(25)       NOT NULL,
        user_role               VARCHAR(20)       NOT NULL,
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_AppUser_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_AppUser_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_AppUser PRIMARY KEY CLUSTERED (user_id)
    );
    PRINT 'Table AppUser created.';
END
GO

-- 7. Vehicle
-- Note: current_soc_pct added for intelligent charging prioritization (justified in README)
IF OBJECT_ID(N'dbo.Vehicle', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Vehicle (
        vin                     VARCHAR(17)       NOT NULL,
        org_id                  INT               NOT NULL,
        user_id                 INT               NOT NULL,
        license_plate           VARCHAR(20)       NOT NULL,
        battery_capacity_kwh    DECIMAL(8,2)      NOT NULL,
        max_charge_rate_kw      DECIMAL(8,2)      NOT NULL,
        current_soc_pct         DECIMAL(5,2)      NOT NULL CONSTRAINT DF_Vehicle_CurrentSoc DEFAULT 50.00,
        ownership_type          VARCHAR(20)       NOT NULL CONSTRAINT DF_Vehicle_OwnershipType DEFAULT 'FLEET',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Vehicle_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Vehicle_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_Vehicle PRIMARY KEY CLUSTERED (vin)
    );
    PRINT 'Table Vehicle created.';
END
GO

-- 8. FleetMission
IF OBJECT_ID(N'dbo.FleetMission', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FleetMission (
        mission_id              INT IDENTITY(1,1) NOT NULL,
        vin                     VARCHAR(17)       NOT NULL,
        driver_id               INT               NOT NULL,
        departure_time          DATETIME2(7)      NOT NULL,
        target_soc_pct          DECIMAL(5,2)      NOT NULL,
        route_distance_km       DECIMAL(8,2)      NOT NULL CONSTRAINT DF_FleetMission_RouteDistance DEFAULT 0.00,
        mission_status          VARCHAR(20)       NOT NULL CONSTRAINT DF_FleetMission_Status DEFAULT 'SCHEDULED',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetMission_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_FleetMission_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_FleetMission PRIMARY KEY CLUSTERED (mission_id)
    );
    PRINT 'Table FleetMission created.';
END
GO

-- 9. Reservation
IF OBJECT_ID(N'dbo.Reservation', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Reservation (
        reservation_id          INT IDENTITY(1,1) NOT NULL,
        bay_id                  INT               NOT NULL,
        vin                     VARCHAR(17)       NOT NULL,
        user_id                 INT               NOT NULL,
        start_time              DATETIME2(7)      NOT NULL,
        end_time                DATETIME2(7)      NOT NULL,
        reservation_status      VARCHAR(20)       NOT NULL CONSTRAINT DF_Reservation_Status DEFAULT 'PENDING',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Reservation_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Reservation_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_Reservation PRIMARY KEY CLUSTERED (reservation_id)
    );
    PRINT 'Table Reservation created.';
END
GO

-- 10. ChargingSession
IF OBJECT_ID(N'dbo.ChargingSession', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ChargingSession (
        session_id              INT IDENTITY(1,1) NOT NULL,
        bay_id                  INT               NOT NULL,
        vin                     VARCHAR(17)       NOT NULL,
        user_id                 INT               NOT NULL,
        reservation_id          INT               NOT NULL,
        start_time              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingSession_StartTime DEFAULT SYSDATETIME(),
        end_time                DATETIME2(7)      NULL,
        allocated_kw            DECIMAL(8,2)      NOT NULL,
        energy_delivered_kwh    DECIMAL(10,3)     NOT NULL CONSTRAINT DF_ChargingSession_Energy DEFAULT 0.000,
        idle_minutes            INT               NOT NULL CONSTRAINT DF_ChargingSession_IdleMin DEFAULT 0,
        status                  VARCHAR(20)       NOT NULL CONSTRAINT DF_ChargingSession_Status DEFAULT 'STARTED',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingSession_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_ChargingSession_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_ChargingSession PRIMARY KEY CLUSTERED (session_id)
    );
    PRINT 'Table ChargingSession created.';
END
GO

-- 11. MaintenanceLog
IF OBJECT_ID(N'dbo.MaintenanceLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MaintenanceLog (
        log_id                  INT IDENTITY(1,1) NOT NULL,
        bay_id                  INT               NOT NULL,
        technician_id           INT               NOT NULL,
        issue_reported          VARCHAR(500)      NOT NULL,
        reported_at             DATETIME2(7)      NOT NULL CONSTRAINT DF_MaintenanceLog_ReportedAt DEFAULT SYSDATETIME(),
        resolved_at             DATETIME2(7)      NULL,
        repair_status           VARCHAR(20)       NOT NULL CONSTRAINT DF_MaintenanceLog_RepairStatus DEFAULT 'OPEN',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_MaintenanceLog_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_MaintenanceLog_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_MaintenanceLog PRIMARY KEY CLUSTERED (log_id)
    );
    PRINT 'Table MaintenanceLog created.';
END
GO

-- 12. Invoice
-- Total amount implemented as PERSISTED computed column for absolute mathematical consistency
IF OBJECT_ID(N'dbo.Invoice', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Invoice (
        invoice_id              INT IDENTITY(1,1) NOT NULL,
        session_id              INT               NOT NULL,
        energy_charge           DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Invoice_EnergyCharge DEFAULT 0.00,
        idle_penalty_charge     DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Invoice_IdlePenalty DEFAULT 0.00,
        tax_amount              DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Invoice_TaxAmount DEFAULT 0.00,
        total_amount            AS (energy_charge + idle_penalty_charge + tax_amount) PERSISTED,
        status                  VARCHAR(20)       NOT NULL CONSTRAINT DF_Invoice_Status DEFAULT 'PENDING',
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Invoice_CreatedAt DEFAULT SYSDATETIME(),
        updated_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Invoice_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_Invoice PRIMARY KEY CLUSTERED (invoice_id)
    );
    PRINT 'Table Invoice created.';
END
GO

-- 13. Payment
IF OBJECT_ID(N'dbo.Payment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Payment (
        payment_id              INT IDENTITY(1,1) NOT NULL,
        invoice_id              INT               NOT NULL,
        payment_method          VARCHAR(20)       NOT NULL,
        paid_amount             DECIMAL(10,2)     NOT NULL,
        transaction_ref         VARCHAR(100)      NOT NULL,
        settled_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Payment_SettledAt DEFAULT SYSDATETIME(),
        created_at              DATETIME2(7)      NOT NULL CONSTRAINT DF_Payment_CreatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_Payment PRIMARY KEY CLUSTERED (payment_id)
    );
    PRINT 'Table Payment created.';
END
GO

PRINT 'All 13 core tables created successfully.';
GO
