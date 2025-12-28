\# Windows Health Check Scripts



This folder contains a modular, read-only Windows diagnostics toolkit designed for fast triage, baseline validation, and repeatable evidence collection. Scripts are structured so you can run individual tests for a specific symptom, or run an orchestrated bundle that writes a timestamped output folder suitable for ticket attachments and long-term tracking.



All scripts are intended to be safe for production use:



\* No registry edits, policy changes, service restarts, or configuration writes

\* Outputs are returned as objects (good for export) and/or written as logs/artifacts by the orchestrator

\* Failures are captured in results instead of silently swallowed



\## Folder Structure



\* `scripts/`

&nbsp; Primary health check scripts and the orchestrator



\* `scripts/\_shared/`

&nbsp; Shared helpers used by multiple scripts (logging, elevation checks, system context)



\## Quick Start



Run the full health bundle and collect a complete report folder:



```powershell

.\\Invoke-WindowsHealthCheck.ps1

```



Write results to a specific output location:



```powershell

.\\Invoke-WindowsHealthCheck.ps1 -OutputRoot "C:\\Reports\\WindowsHealth"

```



Run only specific sections (by section name or script file name):



```powershell

.\\Invoke-WindowsHealthCheck.ps1 -Include 01-Prereqs,05-DiskHealth,08-TimeSync

```



```powershell

.\\Invoke-WindowsHealthCheck.ps1 -Include Test-DiskHealth.ps1,Test-TimeSync.ps1

```



Exclude noisy sections:



```powershell

.\\Invoke-WindowsHealthCheck.ps1 -Exclude 02-CriticalEvents,17-PerformanceBaseline

```



Export a consolidated report from an existing run folder:



```powershell

.\\Export-WindowsHealthReport.ps1 -RunPath "C:\\ProgramData\\TechnicalKB\\WindowsHealth\\SERVER01-20251228-120000" -ExportCsv -ExportText

```



\## Script Catalog



\### Orchestration and Reporting



\*\*Invoke-WindowsHealthCheck.ps1\*\*

Runs the standard suite of Windows health checks, captures outputs into a timestamped run folder, and produces both structured JSON and readable TXT artifacts per section.



When to use:



\* Incident triage (“server is slow”, “patching failed”, “random reboots”)

\* Evidence collection for escalation

\* Pre-change or post-change validation

\* Repeatable baselines for known-good systems



Key outputs:



\* `run.log` (timeline)

\* `00-SystemContext.json/.txt`

\* `Summary.json/.txt`

\* Per-section files (e.g., `05-DiskHealth.json/.txt`)



\*\*Export-WindowsHealthReport.ps1\*\*

Post-processes an existing run folder and produces a consolidated JSON report. Optionally exports CSV and a flattened text summary for ticketing systems.



When to use:



\* You want a single “attachment-friendly” artifact

\* You need to extract “Problems” quickly across sections

\* You want CSV for trending or dashboards



---



\### Prereqs and Context



\*\*Test-WindowsPrereqs.ps1\*\*

Validates baseline prerequisites and collects high-signal environment context (OS, uptime, pending reboot signals, required commands present, OS drive free space).



When to use:



\* Always first during troubleshooting

\* Patch/upgrade readiness validation

\* Identifying “pending reboot” causes for weird behavior



---



\### Events and Logging Signals



\*\*Get-CriticalSystemEvents.ps1\*\*

Collects recent warning/error events from key logs and highlights events with high-signal keywords.



When to use:



\* Fast triage when symptoms are unclear

\* Evidence capture for a change window or incident

\* Spotting disk, update, WMI, WinRM, or driver-related patterns quickly



\*\*Test-EventLogHealth.ps1\*\*

Validates that event logs are accessible and readable (service status, log availability, sample reads, optional wevtutil metadata).



When to use:



\* Logs appear empty or inaccessible

\* Monitoring/RMM depends on event logs

\* You suspect log corruption or access issues



---



\### Services and OS Components



\*\*Test-SystemServices.ps1\*\*

Checks core Windows services for presence and expected running state, with optional dependency mapping and optional service-related event signals.



When to use:



\* OS instability or “random” failures

\* Update failures tied to services

\* WMI/WinRM management issues

\* Baseline validation after hardening changes



---



\### Updates and Reboot State



\*\*Test-WindowsUpdates.ps1\*\*

Checks update-related services, pending reboot indicators, and Windows Update operational warning/error signals (best-effort across OS versions).



When to use:



\* Patching failures or stuck update states

\* Compliance validation

\* Post-patch troubleshooting



\*\*Test-SystemReboots.ps1\*\*

Collects reboot/crash signals (Kernel-Power, unexpected shutdown, bugcheck evidence, planned restart entries) and uptime.



When to use:



\* Random reboot investigations

\* Stability and power issues

\* Post-update incidents with unexpected restarts



---



\### Storage and Capacity



\*\*Test-VolumeFreeSpace.ps1\*\*

Checks local fixed volumes for free space and flags volumes below thresholds (OS volume can have stricter thresholds).



When to use:



\* Patch failures

\* Performance degradation

\* Prior to migrations or large file operations

\* Routine capacity baselines



\*\*Test-DiskHealth.ps1\*\*

Checks storage health signals: SMART predictive failure (best-effort), disk inventory/status, and disk/NTFS/storage warning/error events.



When to use:



\* Disk/NTFS errors

\* Slowness tied to I/O

\* Evidence capture prior to hardware escalation



---



\### Remote Management and Policy



\*\*Test-WinRMHealth.ps1\*\*

Validates WinRM service state, listeners, localhost remoting test, firewall profile state, and optional WinRM event signals.



When to use:



\* Remote PowerShell / RMM failures

\* Automation/orchestration failures

\* WinRM connectivity troubleshooting



\*\*Test-WMIHealth.ps1\*\*

Validates WMI service state and basic CIM/WMI query functionality; optional event signal capture.



When to use:



\* Inventory/RMM failures

\* Scripts failing with CIM/WMI errors

\* “Invalid class” or “RPC server unavailable” errors



\*\*Test-GroupPolicyProcessing.ps1\*\*

Collects Group Policy processing signals and GP-related event errors; includes `gpresult /r` output.



When to use:



\* GPO not applying

\* Slow logons tied to policy processing

\* Missing settings tied to GP



---



\### Security Baseline Signals



\*\*Test-AVStatus.ps1\*\*

Detects installed AV products via SecurityCenter2 when available; optional service scan for common endpoint agents.



When to use:



\* Baseline security checks

\* Incident triage

\* Verifying server endpoint protection presence



\*\*Test-DefenderHealth.ps1\*\*

Reports Defender health using `Get-MpComputerStatus` when available, including signature state and protection status.



When to use:



\* Defender validation and troubleshooting

\* Confirming signature freshness and real-time protection



\*\*Test-FirewallStatus.ps1\*\*

Reports Windows Firewall profile states and service health; optional sampling of inbound allow rules.



When to use:



\* Hardening verification

\* Connectivity issues that may be firewall-related

\* Incident response evidence



---



\### Startup and Performance



\*\*Test-StartupFailures.ps1\*\*

Collects boot/startup failure signals and driver/service initialization issues from event logs; includes Diagnostics-Performance log when present.



When to use:



\* Slow boot investigations

\* Driver failures after updates

\* Service start failures on reboot



\*\*Test-PerformanceBaselines.ps1\*\*

Captures a lightweight performance snapshot: CPU, memory, disk perf counters (if available), and top CPU/memory processes.



When to use:



\* “Server is slow” triage

\* Post-patch performance regression

\* Quick baselines for trending and escalation evidence



---



\### Time Synchronization



\*\*Test-TimeSync.ps1\*\*

Evaluates W32Time service/configuration and collects time source, status, and recent W32Time warning/error events. Optional stripchart sampling.



When to use:



\* Kerberos/authentication issues

\* Clock drift or time source concerns

\* Baseline validation for critical servers



\## Shared Helpers



\### scripts/\_shared/



\*\*Write-HealthLog.ps1\*\*

Standardized logging helper (console + optional file log) with severity levels.



\*\*Assert-RunAsAdmin.ps1\*\*

Validation helper to ensure the session is elevated (does not attempt to self-elevate).



\*\*Get-SystemContext.ps1\*\*

Lightweight baseline environment snapshot used by orchestrators and report exports.



\## Output and Evidence



The orchestrator writes a run folder containing:



\* A run log (`run.log`) for timeline context

\* Per-check JSON outputs (machine-readable)

\* Per-check TXT outputs (human-readable)



This structure supports:



\* Ticket attachments

\* Escalations to vendors/Microsoft

\* Trending and comparisons across time or across systems



