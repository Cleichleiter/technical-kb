

````markdown

\# Active Directory – Domain Controller Health Check Scripts



This folder contains a curated collection of \*\*read-only PowerShell diagnostic scripts\*\* designed to assess the health of an Active Directory Domain Controller (DC).



These scripts are intended to support:

\- Incident response

\- Pre-/post-change validation

\- Environment baselining

\- Evidence collection for tickets and escalations

\- Knowledge Base documentation



They focus on \*\*signal over noise\*\* and avoid making any changes to the environment.



---



\## Design Principles



\- \*\*Read-only / non-destructive\*\*

\- \*\*DC-safe\*\* (no repair, no remediation, no writes)

\- \*\*Structured output\*\* (objects suitable for JSON, CSV, or text export)

\- \*\*Composable\*\* (each script can run independently or via an orchestrator)

\- \*\*Evidence-first\*\* (captures raw outputs where helpful)



---



\## Recommended Usage Order



For a full health assessment, run the scripts in this order:



1\. `Test-DCPrereqs.ps1`

2\. `Get-ADCriticalEvents.ps1`

3\. `Test-DCDiag.ps1`

4\. `Test-ADReplication.ps1`

5\. `Test-DNSHealth.ps1`

6\. `Test-SYSVOLDFSR.ps1`

7\. `Test-TimeSync.ps1`

8\. `Test-DCServices.ps1`

9\. `Test-NTDSDatabase.ps1`



Or run everything at once using:



```powershell

.\\Invoke-DCHealthCheck.ps1

````



---



\## Script Index



\### Invoke-DCHealthCheck.ps1



\*\*Purpose:\*\*

Primary orchestrator. Runs all DC health checks in sequence and writes results to a timestamped output folder.



\*\*Use when:\*\*



\* You need a single-command DC health snapshot

\* Collecting evidence during an incident

\* Pre/post maintenance validation



---



\### Test-DCPrereqs.ps1



\*\*Purpose:\*\*

Validates prerequisites and baseline context before deeper diagnostics.



\*\*Checks include:\*\*



\* Domain Controller role detection

\* Elevated session validation

\* Required binaries (dcdiag, repadmin, etc.)

\* Core service presence

\* AD module availability

\* DNS client configuration

\* Local listening ports



\*\*Use when:\*\*

Other scripts fail unexpectedly or you want environment context first.



---



\### Get-ADCriticalEvents.ps1



\*\*Purpose:\*\*

Collects high-signal Warning/Error events from AD-relevant logs.



\*\*Logs queried:\*\*



\* System

\* Directory Service

\* DNS Server

\* DFS Replication

\* KDC

\* (Optional) Security



\*\*Use when:\*\*

You need fast evidence of \*why\* a DC is unhealthy.



---



\### Test-DCDiag.ps1



\*\*Purpose:\*\*

Runs `dcdiag.exe` with a controlled test set and extracts failures.



\*\*Checks include:\*\*



\* Advertising

\* Services

\* Replication

\* DNS

\* SYSVOL

\* KCC/topology

\* FSMO awareness



\*\*Use when:\*\*

Performing a primary AD health assessment.



---



\### Test-ADReplication.ps1



\*\*Purpose:\*\*

Assesses Active Directory replication health.



\*\*Checks include:\*\*



\* `repadmin /replsummary`

\* `repadmin /showrepl`

\* Replication queue depth

\* Failure cache

\* DC locator and secure channel validation



\*\*Use when:\*\*

Replication, GPO, or authentication issues are suspected.



---



\### Test-DNSHealth.ps1



\*\*Purpose:\*\*

Validates DNS configuration and AD-critical DNS records.



\*\*Checks include:\*\*



\* DNS Server service status

\* DNS client settings

\* SRV, SOA, and NS records required by AD

\* Optional local vs server-specific resolution

\* Optional DC host A/AAAA record validation



\*\*Use when:\*\*

Any AD issue might be DNS-related (which is most of them).



---



\### Test-SYSVOLDFSR.ps1



\*\*Purpose:\*\*

Checks SYSVOL and DFS Replication health.



\*\*Checks include:\*\*



\* SYSVOL and NETLOGON shares

\* DFSR service status

\* DFSR migration state

\* SYSVOL folder presence

\* Recent DFS Replication warnings/errors



\*\*Use when:\*\*

GPOs are not applying or SYSVOL inconsistency is suspected.



---



\### Test-TimeSync.ps1



\*\*Purpose:\*\*

Evaluates Windows Time configuration and health.



\*\*Checks include:\*\*



\* W32Time service status

\* Time source and peers

\* Configuration details

\* Recent time-related events

\* Optional NTP stripchart

\* Optional PDC Emulator identification



\*\*Use when:\*\*

Kerberos errors, logon failures, or inconsistent DC behavior occurs.



---



\### Test-DCServices.ps1



\*\*Purpose:\*\*

Validates core DC services and highlights service-related issues.



\*\*Checks include:\*\*



\* Service presence

\* Running state

\* Start type

\* Optional dependency mapping

\* Optional Service Control Manager events



\*\*Use when:\*\*

A DC feels unstable or services appear degraded.



---



\### Test-NTDSDatabase.ps1



\*\*Purpose:\*\*

Performs safe checks related to the Active Directory database (NTDS.dit).



\*\*Checks include:\*\*



\* Database and log file paths

\* File existence and size (optional)

\* Disk free space

\* NTDS service status

\* ESENT (ESE) warnings/errors

\* Optional Directory Service log correlation



\*\*Use when:\*\*

Storage issues, ESENT errors, or NTDS instability are suspected.



---



\## Output Notes



\* All scripts return structured PowerShell objects.

\* Designed for:



&nbsp; \* `ConvertTo-Json`

&nbsp; \* `Export-Csv`

&nbsp; \* Text capture via `Out-String`

\* No script makes changes to AD, DNS, SYSVOL, or time configuration.



---



\## Safety Notice



These scripts are \*\*diagnostic only\*\*.



They do \*\*not\*\*:



\* Modify configuration

\* Restart services

\* Repair AD

\* Run esentutl repairs

\* Trigger DFSR changes



They are safe to run in production environments when executed with appropriate privileges.



---



\## Author / Maintainer



Maintained as part of the \*\*Technical KB – Active Directory\*\* knowledge base.

Designed for real-world troubleshooting, documentation, and escalation workflows.



```



---





