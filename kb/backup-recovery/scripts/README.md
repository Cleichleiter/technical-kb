\# Backup \& Recovery Scripts



This folder contains production-safe PowerShell scripts used to assess backup readiness, identify common failure conditions, and collect evidence for troubleshooting backup and restore issues. The scripts are intentionally vendor-agnostic and focus on Windows-native signals (VSS, event logs, volume health, restore artifacts) that commonly impact backup tooling.



The scripts can be run individually, or executed as a standardized bundle using the orchestrator.



---



\## Purpose



Use this script set to:



\* Validate baseline backup prerequisites (services, tooling availability, system signals)

\* Detect VSS writer failures and snapshot instability

\* Identify storage conditions that commonly break backups (low free space, degraded volumes)

\* Estimate last-known backup activity using Windows-native indicators

\* Collect high-signal backup/VSS-related event logs for incident timelines

\* Validate minimum local restore readiness signals

\* Produce consistent, reportable artifacts for tickets, escalations, and audits



All scripts are:



\* Safe for production environments

\* Read-only by default (except optional target write-test, which creates and deletes a tiny temp file)

\* Designed for repeatable evidence collection



---



\## Folder Structure



\* `\_shared`

&nbsp; Shared helper functions used across scripts (logging, elevation checks)



\* Root `scripts` folder

&nbsp; Individual checks and orchestration/reporting scripts



---



\## Script Overview and When to Use



\### Orchestration and Reporting



\*\*Invoke-BackupHealthCheck.ps1\*\*

Runs a standardized sequence of backup/recovery checks and writes a timestamped run folder containing JSON artifacts and a summary index.

Use this during incidents, onboarding assessments, pre-change validation, and post-change verification.



\*\*Export-BackupHealthReport.ps1\*\*

Consolidates a run folder into a single JSON report and optional CSV/TXT summaries.

Use this to attach evidence to tickets, create audit artifacts, or produce an executive summary of failures.



---



\### Evidence Collection



\*\*Get-BackupCriticalEvents.ps1\*\*

Collects high-signal Windows event log entries commonly associated with backup failures and VSS issues.

Use this when a backup job fails and you need context, root-cause signals, or a timeline.



\*\*Get-BackupInventory.ps1\*\*

Creates a vendor-agnostic backup inventory snapshot (OS details, Windows Server Backup presence, VSS providers, volumes, shadow copies).

Use this for baselining and documentation, especially during onboarding or before migrations.



---



\### Target Validation



\*\*Get-BackupTargetHealth.ps1\*\*

Validates basic reachability and health signals for a backup target path (local or UNC). Optional write-test available.

Use this when backups to a NAS/share fail, targets become intermittently unavailable, or permissions are suspected.



---



\### Health Checks



\*\*Test-BackupPrereqs.ps1\*\*

Validates common prerequisites (RPC/VSS/COM+, tools present, CIM availability).

Use this early in troubleshooting when backups are failing broadly or VSS checks are returning inconsistent results.



\*\*Test-VSSWriters.ps1\*\*

Parses `vssadmin list writers` and flags unstable writers or writer errors.

Use this when backups fail at snapshot creation, application-aware backups fail, or databases/services are involved.



\*\*Test-BackupStorage.ps1\*\*

Checks volume health and free space thresholds that commonly cause backup failures.

Use this when backups fail due to space constraints, snapshot issues, or backup staging problems.



\*\*Test-BackupRestorePoint.ps1\*\*

Checks for the presence of local recovery artifacts such as shadow copies and (where applicable) restore points.

Use this to validate that snapshot-based recovery signals exist on systems where that is expected.



\*\*Test-LastBackupAge.ps1\*\*

Estimates “time since last backup” using Windows-native indicators (latest shadow copy and/or Windows Backup event).

Use this to quickly identify systems that may be out of compliance or have stale backup signals. This is a heuristic and should be validated against vendor backup consoles when available.



\*\*Test-BareMinimumRestoreReadiness.ps1\*\*

Evaluates minimum restore readiness signals (free space, VSS writer stability, WinRE status where applicable).

Use this when preparing for major changes, validating disaster recovery posture, or confirming basic restore feasibility.



---



\## Typical Usage



Run a full backup/recovery health check (creates a timestamped run folder):



```powershell

.\\Invoke-BackupHealthCheck.ps1

```



Run a full check with a backup target path:



```powershell

.\\Invoke-BackupHealthCheck.ps1 -TargetPath "\\\\NAS01\\Backups\\Server01"

```



Export a consolidated report from a run folder:



```powershell

.\\Export-BackupHealthReport.ps1 -RunPath "C:\\Reports\\BackupHealth\\Run\_2025-12-28\_125900" -ExportCsv -ExportText

```



Run focused checks during troubleshooting:



```powershell

.\\Test-VSSWriters.ps1

.\\Get-BackupCriticalEvents.ps1 -DaysBack 7 -MaxEvents 300

.\\Test-BackupStorage.ps1

```



---



\## Notes and Limitations



\* These scripts validate Windows-native signals and common failure conditions; they do not validate vendor backup chain integrity.

\* `Test-LastBackupAge.ps1` is an estimate based on local indicators. Always confirm against the backup platform console when available.

\* Some checks may require elevation depending on environment hardening, logging configuration, or OS SKU.



---



