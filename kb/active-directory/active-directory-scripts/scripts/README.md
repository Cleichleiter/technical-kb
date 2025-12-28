# Active Directory – Domain Controller Health Check Scripts

This folder contains a curated collection of read-only PowerShell diagnostic scripts designed to assess the health of an Active Directory Domain Controller (DC).

These scripts are intended to support:

* Incident response
* Pre-/post-change validation
* Environment baselining
* Evidence collection for tickets and escalations
* Technical Knowledge Base documentation

They prioritize signal over noise and do not make changes to the environment.

---

## Design Principles

* Read-only and non-destructive
* Safe to run on production Domain Controllers
* Structured output suitable for logging and export
* Modular and composable (scripts run independently or together)
* Evidence-first diagnostics for troubleshooting and escalation

---

## Recommended Usage Order

For a full DC health assessment, run the scripts in the following order:

1. Test-DCPrereqs.ps1
2. Get-ADCriticalEvents.ps1
3. Test-DCDiag.ps1
4. Test-ADReplication.ps1
5. Test-DNSHealth.ps1
6. Test-SYSVOLDFSR.ps1
7. Test-TimeSync.ps1
8. Test-DCServices.ps1
9. Test-NTDSDatabase.ps1

To run the full suite in one pass, use the orchestrator script:

```powershell
.\Invoke-DCHealthCheck.ps1
```

---

## Script Index

### Invoke-DCHealthCheck.ps1

Primary orchestrator that runs all Domain Controller health checks in sequence and aggregates results.

Use when:

* A full DC health snapshot is required
* Collecting evidence during an incident
* Performing pre- or post-maintenance validation

---

### Test-DCPrereqs.ps1

Validates prerequisites and baseline environment context before running deeper diagnostics.

Checks include:

* Domain Controller role detection
* Elevated session validation
* Required diagnostic tools availability
* Core service presence
* AD module availability
* DNS client configuration
* Local listening ports

Use when:

* Other scripts fail unexpectedly
* You need environment context before troubleshooting

---

### Get-ADCriticalEvents.ps1

Collects high-signal warning and error events from Active Directory–relevant logs.

Logs queried:

* System
* Directory Service
* DNS Server
* DFS Replication
* KDC
* Optional Security log

Use when:

* You need fast evidence explaining DC instability

---

### Test-DCDiag.ps1

Runs dcdiag with a controlled test set and extracts failures and warnings.

Checks include:

* Advertising
* Services
* Replication
* DNS
* SYSVOL
* KCC and topology
* FSMO role awareness

Use when:

* Performing a primary AD health assessment

---

### Test-ADReplication.ps1

Assesses Active Directory replication health.

Checks include:

* Replication summary
* Partner replication status
* Replication queue depth
* Failure cache
* Secure channel and DC locator validation

Use when:

* Replication, GPO, or authentication issues are suspected

---

### Test-DNSHealth.ps1

Validates DNS configuration and AD-critical DNS records.

Checks include:

* DNS Server service status
* DNS client server configuration
* Required SRV, SOA, and NS records
* Optional local vs server-specific resolution tests
* Optional DC host A/AAAA record checks

Use when:

* Any AD issue may be DNS-related

---

### Test-SYSVOLDFSR.ps1

Checks SYSVOL and DFS Replication health.

Checks include:

* SYSVOL and NETLOGON share presence
* DFSR service status
* DFSR migration state
* SYSVOL folder structure validation
* Recent DFS Replication warnings and errors

Use when:

* Group Policy is not applying
* SYSVOL inconsistency is suspected

---

### Test-TimeSync.ps1

Evaluates Windows Time configuration and synchronization health.

Checks include:

* W32Time service status and start type
* Time source and peer configuration
* Time-related warnings and errors
* Optional NTP stripchart sampling
* Optional PDC Emulator identification

Use when:

* Kerberos or authentication issues occur
* Time skew or clock drift is suspected

---

### Test-DCServices.ps1

Validates core Domain Controller services and highlights service-related issues.

Checks include:

* Service presence
* Running state
* Start type validation
* Optional dependency mapping
* Optional Service Control Manager event review

Use when:

* A DC feels unstable or partially degraded

---

### Test-NTDSDatabase.ps1

Performs safe checks related to the Active Directory database (NTDS.dit).

Checks include:

* Database and log file paths
* File existence and size (optional)
* Disk free space on hosting volumes
* NTDS service status
* ESENT warnings and errors
* Optional Directory Service log correlation

Use when:

* Storage issues or ESENT errors are present
* NTDS instability is suspected

---

## Output Notes

* All scripts return structured PowerShell objects
* Suitable for JSON, CSV, or text export
* No script modifies Active Directory, DNS, SYSVOL, DFSR, or time configuration

---

## Safety Notice

These scripts are diagnostic only.

They do not:

* Modify configuration
* Restart services
* Repair Active Directory
* Run esentutl repairs
* Trigger DFS Replication changes

They are safe to run in production environments when executed with appropriate privileges.
