-- ============================================================================
-- SCRIPT: 01_create_database.sql
-- SYSTEM: Intelligent EV Charging Station and Fleet/Depot Management System
-- DIALECT: Microsoft SQL Server (T-SQL)
-- DESCRIPTION: Creates the database if it does not already exist, sets proper
--              collation, recovery model, and snapshot isolation.
-- ============================================================================

USE master;
GO

-- Terminate active connections and drop existing database if recreation is required
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'EVChargingDB')
BEGIN
    PRINT 'Existing database EVChargingDB found. Setting to SINGLE_USER and dropping...';
    ALTER DATABASE EVChargingDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EVChargingDB;
    PRINT 'Database EVChargingDB dropped successfully.';
END
GO

PRINT 'Creating database EVChargingDB...';
CREATE DATABASE EVChargingDB
COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

-- Configure optimal database settings for transactional integrity and concurrency
ALTER DATABASE EVChargingDB SET RECOVERY FULL;
ALTER DATABASE EVChargingDB SET ALLOW_SNAPSHOT_ISOLATION ON;
ALTER DATABASE EVChargingDB SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE EVChargingDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE EVChargingDB SET ANSI_NULL_DEFAULT ON;
ALTER DATABASE EVChargingDB SET ANSI_NULLS ON;
ALTER DATABASE EVChargingDB SET ANSI_PADDING ON;
ALTER DATABASE EVChargingDB SET ANSI_WARNINGS ON;
ALTER DATABASE EVChargingDB SET CONCAT_NULL_YIELDS_NULL ON;
ALTER DATABASE EVChargingDB SET QUOTED_IDENTIFIER ON;
GO

USE EVChargingDB;
GO

PRINT 'Database EVChargingDB created and configured successfully.';
GO
