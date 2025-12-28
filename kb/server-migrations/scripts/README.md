# Server Migration Preflight Scripts

## Purpose

This folder contains PowerShell scripts used to perform a **pre-migration discovery and readiness assessment** for server-to-server data migrations (file servers, application servers with data dependencies, and mixed workloads).

The goal is to gather the technical evidence required to:

* Size and build the target server correctly
* Recreate file sharing and access models accurately
* Identify services, scheduled tasks, and applications that depend on the data
* Reduce cutover risk by identifying locks, namespace dependencies, and operational health signals
* Produce an auditable artifact set that can be attached to tickets, change records, or project phases

These scripts are designed for **repeatable execution** and consistent output formatting.

---

## Scope and Assumptions

These scripts are intended to be run:

* Primarily on the **source server** (the server being migrated)
* In a **PowerShell session running as Administrator** (some collectors require elevated access)
* During a period where discovery is allowed (some scripts collect active SMB sessions and open files)

The scripts do not migrate data. They only collect information needed to plan and validate a migration.

---

## Output Location and Artifact Format

All scripts write outputs into a standardized report folder created per run:

* `server-migrations\reports\<ServerName>\Preflight_YYYYMMDD_HHMMSS\`

Artifacts include JSON, CSV, and TXT outputs to support:

* Human review
* Ticket attachment
* Post-migration validation comparisons
* Automation and parsing in future workflows

A `migration.log` file is also written to the run folder when invoked through the orchestrator.

---

## Recommended Execution Workflow

1. Run the orchestrator to create a full evidence package
2. Review artifacts and complete the migration risk checklist
3. Resolve or accept identified risks
4. Re-run preflight if major changes occur before cutover

---

## Script Inventory

### Orchestrator

* `Invoke-ServerMigrationPreflight.ps1`
  Runs all collectors in a standard order and writes results into a single run folder.

### Collectors

* `Get-ServerPlatformSummary.ps1`
  Captures OS/platform context, uptime, hotfix subset, network adapter inventory, and IP addressing signals.

* `Get-ServerStorageInventory.ps1`
  Exports disks, partitions, and volumes for sizing and layout validation.

* `Get-FileShareInventory.ps1`
  Exports SMB shares and share-level permissions.

* `Export-NtfsAclSnapshot.ps1`
  Captures NTFS ACL snapshots for share roots (or provided paths). Designed to be practical for preflight use with a controlled traversal depth.

* `Get-SmbActivitySnapshot.ps1`
  Captures SMB sessions and open files to identify locked-file risk and cutover impact.

* `Get-ServiceInventory.ps1`
  Exports Windows services, startup type, and run-as identities.

* `Get-ScheduledTaskExport.ps1`
  Exports scheduled task inventory including run-as context and action/trigger summaries.

* `Get-InstalledSoftwareInventory.ps1`
  Captures installed software from registry uninstall keys (32-bit and 64-bit).

* `Test-BackupReadinessSnapshot.ps1`
  Captures VSS writers/shadow storage output and recent backup/VSS-related event log signals.

* `Get-DfsConfigurationSnapshot.ps1`
  Captures DFS Namespace and DFS Replication configuration when DFS tools are available.

* `Get-IisConfigurationSnapshot.ps1`
  Captures IIS sites, bindings, and app pools when IIS management tools are available.

* `Get-PrintServerInventory.ps1`
  Captures printers, ports, and drivers when PrintManagement tools are available.

* `Get-MigrationRiskEventLogSummary.ps1`
  Captures recent critical/error events correlated with migration instability risk (disk/NTFS/SMB/VSS/time/auth signals).

### Shared Utilities

Shared helpers are stored under `_shared` and are dot-sourced by the orchestrator and scripts as needed:

* `_shared\Assert-RunAsAdmin.ps1`
  Ensures the session is elevated and fails fast if not.

* `_shared\New-MigrationReportFolder.ps1`
  Creates the standardized report folder structure and returns key paths.

* `_shared\Write-MigrationLog.ps1`
  Provides consistent console + file logging.

---

## Usage

Run the orchestrator from the `scripts` folder:

```powershell
.\Invoke-ServerMigrationPreflight.ps1
```

Run against a specific server name label (for output folder naming):

```powershell
.\Invoke-ServerMigrationPreflight.ps1 -ServerName FS01
```

Exclude Microsoft scheduled tasks when running the scheduled task collector directly:

```powershell
.\Get-ScheduledTaskExport.ps1 -OutputRoot 'C:\Temp\Preflight' -ExcludeMicrosoft
```

Run the NTFS ACL snapshot against specific data roots:

```powershell
.\Export-NtfsAclSnapshot.ps1 -OutputRoot 'C:\Temp\Preflight' -Paths 'D:\Data','E:\Shares' -MaxDepth 2
```

---

## Notes and Limitations

* Some collectors require Windows features or RSAT modules:

  * DFS cmdlets require DFSN/DFSR management tooling
  * IIS cmdlets require IIS management tooling (WebAdministration)
  * Print cmdlets require PrintManagement
    When not available, the scripts write a note file indicating the dependency.

* Preflight artifacts should be treated as **read-only evidence**. Do not modify outputs after collection.

* If the environment changes materially (new shares, permissions changes, application changes), re-run the orchestrator and store a new run folder.

---

## Related KB Articles

* `..\kb\server-migration-preflight-overview.md`
* `..\kb\data-migration-risk-checklist.md`
* `..\kb\cutover-readiness-validation.md`
