\# Cloud



A curated set of PowerShell scripts for assessing and troubleshooting cloud identity and Azure platform health. This folder is designed for rapid triage, repeatable evidence collection, and consistent outputs that can be attached to tickets or used during project discovery.



These scripts are written to be safe in production environments and focus on read-only diagnostics unless explicitly stated (for example, triggering an Entra Connect sync cycle).



---



\## Folder Structure



\* `scripts\\\_shared\\`



&nbsp; \* Shared functions used by multiple scripts (logging, elevation checks, module validation)

\* `scripts\\`



&nbsp; \* Standalone checks and orchestrators



---



\## General Guidance



\### Requirements



\* Windows PowerShell 5.1+ or PowerShell 7+

\* Azure checks require the Az PowerShell modules (varies by script)

\* Entra ID / Microsoft 365 checks require Microsoft Graph PowerShell modules and appropriate permissions

\* Entra Connect (Azure AD Connect) checks must be run on the Entra Connect server



\### Outputs



\* Most scripts return objects to the pipeline so results can be:



&nbsp; \* formatted as tables

&nbsp; \* exported to JSON/CSV

&nbsp; \* attached to incidents or change records

\* `Invoke-CloudHealthCheck.ps1` creates a run folder and writes JSON artifacts per section plus a consolidated `Summary.json`



\### Safety



\* Scripts are read-only by default.

\* The only script that triggers changes is the Entra Connect sync trigger (`Invoke-AADConnectSync.ps1` / delta sync variants), which runs a sync cycle on demand.



---



\## Script Index



\### Shared Helpers (`scripts\\\_shared`)



\*\*Write-CloudLog.ps1\*\*



\* Purpose: Standard logging function (console + optional file logging).

\* Use when: Writing consistent evidence logs across scripts.



\*\*Assert-RunAsAdmin.ps1\*\*



\* Purpose: Ensures the session is elevated when required.

\* Use when: A script needs admin context (local file paths under ProgramData, module installs, service inspection).



\*\*Assert-Module.ps1\*\*



\* Purpose: Verifies required PowerShell modules are installed/importable.

\* Use when: A script depends on Az or Graph modules and you want consistent handling of missing modules.



---



\## Orchestration



\### Invoke-CloudHealthCheck.ps1



Runs a standardized cloud diagnostic workflow and writes evidence artifacts to a run folder.



Use when:



\* you want a consistent “one-click” health check

\* you need evidence to attach to a ticket/change record

\* you want repeatable results across customers/environments



Script examples:



```powershell

\# Run all checks (default) and write artifacts to ProgramData

.\\Invoke-CloudHealthCheck.ps1



\# Target a specific subscription

.\\Invoke-CloudHealthCheck.ps1 -SubscriptionId <SUBSCRIPTION\_ID>



\# Run only Azure checks

.\\Invoke-CloudHealthCheck.ps1 -Include Azure -SubscriptionId <SUBSCRIPTION\_ID>



\# Run only Entra checks (Graph permissions required)

.\\Invoke-CloudHealthCheck.ps1 -Include Entra



\# Skip a specific section by name

.\\Invoke-CloudHealthCheck.ps1 -Skip 06-AzureKeyVaultHealth

```



---



\## Azure Platform Checks



\### Test-AzureConnectivity.ps1



Validates Azure authentication and optionally sets subscription context.



Use when:



\* scripts fail due to missing context

\* you need to confirm tenant/subscription targeting

\* you are troubleshooting auth issues or expired sessions



Script examples:



```powershell

\# Validate current Azure context or prompt for sign-in

.\\Test-AzureConnectivity.ps1



\# Force subscription context

.\\Test-AzureConnectivity.ps1 -SubscriptionId <SUBSCRIPTION\_ID>



\# Target a specific tenant during login

.\\Test-AzureConnectivity.ps1 -TenantId <TENANT\_ID> -SubscriptionId <SUBSCRIPTION\_ID>

```



\### Get-AzureSubscriptionInventory.ps1



Collects a lightweight subscription inventory snapshot (counts + VM state summary).



Use when:



\* environment discovery

\* baseline evidence for assessments

\* quick “what exists here” snapshot before deeper work



Script examples:



```powershell

\# Inventory the current subscription context

.\\Get-AzureSubscriptionInventory.ps1



\# Inventory a specific subscription

.\\Get-AzureSubscriptionInventory.ps1 -SubscriptionId <SUBSCRIPTION\_ID>

```



\### Test-AzureRBAC.ps1



Surfaces high-signal RBAC risks at subscription scope (owners, contributors, unresolved principals).



Use when:



\* investigating over-privileged access

\* auditing owner sprawl

\* troubleshooting “who has access” questions



Script examples:



```powershell

\# RBAC review in current subscription

.\\Test-AzureRBAC.ps1



\# RBAC review in a specific subscription

.\\Test-AzureRBAC.ps1 -SubscriptionId <SUBSCRIPTION\_ID>

```



\### Test-AzurePolicyCompliance.ps1



Returns top noncompliant policy definitions and noncompliant state counts (Policy Insights).



Use when:



\* compliance reporting

\* identifying top governance violations

\* validating guardrails during hardening projects



Script examples:



```powershell

\# Policy compliance snapshot

.\\Test-AzurePolicyCompliance.ps1



\# Policy compliance snapshot (top 50)

.\\Test-AzurePolicyCompliance.ps1 -Top 50 -SubscriptionId <SUBSCRIPTION\_ID>

```



\### Test-AzureResourceLocks.ps1



Enumerates locks and provides a sample of “critical-ish” resources missing any lock (heuristic).



Use when:



\* assessing deletion protection posture

\* validating critical resources are protected against accidental deletes

\* building governance baselines



Script examples:



```powershell

\# Review locks and unlocked critical resource sample

.\\Test-AzureResourceLocks.ps1



\# Increase sample size

.\\Test-AzureResourceLocks.ps1 -MaxUnlockedSample 100

```



\### Test-AzureKeyVaultHealth.ps1



Inventories Key Vaults and captures governance/security posture (soft delete, purge protection, network posture). Optional access test lists secret metadata (not values).



Use when:



\* Key Vault posture validation (purge protection, network controls)

\* diagnosing Key Vault access issues

\* pre-audit evidence collection



Script examples:



```powershell

\# Key Vault posture inventory

.\\Test-AzureKeyVaultHealth.ps1



\# Include a best-effort access test (secret metadata list)

.\\Test-AzureKeyVaultHealth.ps1 -IncludeAccessTest



\# Target a specific subscription

.\\Test-AzureKeyVaultHealth.ps1 -SubscriptionId <SUBSCRIPTION\_ID> -IncludeAccessTest

```



\### Test-AzureBackupHealth.ps1



Inventories Recovery Services vaults and backup items with a small job sample (best-effort).



Use when:



\* verifying backup coverage

\* troubleshooting backup failures

\* validating vault inventory during assessments



Script examples:



```powershell

\# Backup health inventory

.\\Test-AzureBackupHealth.ps1



\# Increase job sample size

.\\Test-AzureBackupHealth.ps1 -MaxJobs 100

```



\### Test-AzureAVDHealth.ps1



Inventories AVD host pools and session hosts, highlighting session host status and AllowNewSession flags (best-effort).



Use when:



\* AVD sessions failing or hosts unhealthy

\* identifying hosts in drain mode / not accepting sessions

\* baseline inventory for AVD environments



Script examples:



```powershell

\# AVD inventory + session host status

.\\Test-AzureAVDHealth.ps1



\# Target a specific subscription

.\\Test-AzureAVDHealth.ps1 -SubscriptionId <SUBSCRIPTION\_ID>

```



---



\## Entra ID / Microsoft 365 Checks



\### Test-EntraIDDirectoryHealth.ps1



Collects basic tenant and directory role signals using Microsoft Graph.



Use when:



\* validating tenant context

\* verifying directory role enablement visibility

\* evidence collection for identity assessments



Script examples:



```powershell

\# Run assuming Graph is already connected

.\\Test-EntraIDDirectoryHealth.ps1



\# Connect if needed (delegated auth)

.\\Test-EntraIDDirectoryHealth.ps1 -ConnectIfNeeded



\# Include user/group counts (can be slower in large tenants)

.\\Test-EntraIDDirectoryHealth.ps1 -ConnectIfNeeded -IncludeCounts

```



\### Get-M365ServiceHealth.ps1



Retrieves Microsoft 365 service health (health overviews and issues) using Microsoft Graph.



Use when:



\* confirming whether Microsoft has an active incident/advisory

\* correlating user reports with service health

\* providing evidence during escalations



Script examples:



```powershell

\# Run assuming Graph is already connected

.\\Get-M365ServiceHealth.ps1



\# Connect if needed (requires ServiceHealth.Read.All)

.\\Get-M365ServiceHealth.ps1 -ConnectIfNeeded

```



---



\## Entra Connect (Azure AD Connect) – On-Prem Sync



These scripts must be run on the Entra Connect server.



\### Test-AADConnectPrereqs.ps1



Checks for ADSync service/module and scheduler state.



Use when:



\* confirming the correct server

\* diagnosing “sync not running”

\* verifying staging mode / scheduler enabled



Script examples:



```powershell

.\\Test-AADConnectPrereqs.ps1



\# Require elevation (optional)

.\\Test-AADConnectPrereqs.ps1 -RequireAdmin

```



\### Get-AADConnectSyncErrors.ps1



Pulls high-signal warnings/errors related to ADSync/MIIS/providers from event logs.



Use when:



\* objects not syncing

\* exports failing

\* needing evidence for escalation



Script examples:



```powershell

\# Last 7 days (default)

.\\Get-AADConnectSyncErrors.ps1



\# Last 30 days

.\\Get-AADConnectSyncErrors.ps1 -DaysBack 30 -MaxEvents 800

```



\### Invoke-AADConnectSync.ps1



Triggers a sync cycle. Supports Delta or Initial.



Use when:



\* forcing a delta after critical changes

\* validating the pipeline after repairs

\* controlled troubleshooting (use Delta first)



Script examples:



```powershell

\# Delta sync (recommended first)

.\\Invoke-AADConnectSync.ps1 -PolicyType Delta



\# Initial sync (full policy; use intentionally)

.\\Invoke-AADConnectSync.ps1 -PolicyType Initial

```



---



\## Reporting



\### Export-CloudHealthReport.ps1



Consolidates a run folder into a single JSON file and optionally generates CSV/TXT summaries.



Use when:



\* attaching a single consolidated artifact to tickets

\* generating a failure-only CSV for quick review

\* producing a text summary for incident notes



Script examples:



```powershell

\# Consolidate a run folder

.\\Export-CloudHealthReport.ps1 -RunPath "C:\\ProgramData\\TechnicalKB\\CloudHealth\\<RUN\_FOLDER>"



\# Also export CSV and TXT

.\\Export-CloudHealthReport.ps1 -RunPath "C:\\ProgramData\\TechnicalKB\\CloudHealth\\<RUN\_FOLDER>" -ExportCsv -ExportText

```



