\# Server Migration Preflight Overview



\## Purpose



This knowledge base article defines the \*\*server migration preflight process\*\* and establishes the scope, intent, and expected outputs of pre-migration data collection.



A migration preflight is a structured discovery phase performed \*\*before\*\* any data is copied, services are moved, or cutover plans are finalized. Its purpose is to eliminate unknowns, reduce migration risk, and ensure the target server is built and configured with full awareness of the source environment.



This document applies specifically to \*\*server-to-server data migrations\*\*, including file servers, application servers with data dependencies, and hybrid workloads.



---



\## What a Preflight Is — and Is Not



A migration preflight \*\*is\*\*:



\* A factual snapshot of the source server’s current state

\* A risk-identification exercise

\* An input into sizing, design, and cutover planning

\* A defensible record of “what existed” prior to migration



A migration preflight \*\*is not\*\*:



\* A health remediation project

\* A guarantee that no issues will occur during migration

\* A replacement for backups or rollback planning

\* An approval to proceed without review



---



\## Why Preflight Matters



Server migrations fail or degrade most often due to \*\*missing context\*\*, not tooling.



Common failure modes include:



\* Undocumented file shares or permissions

\* Scheduled tasks or services running under unknown identities

\* Applications using local paths assumed to be “just data”

\* Locked files or long-path issues discovered too late

\* Undersized target storage due to hidden mount points

\* Forgotten print services, IIS sites, or background jobs



A preflight exists to surface these risks \*\*before\*\* migration work begins.



---



\## Preflight Scope



The preflight process is designed to capture information across six core domains:



\### 1. Platform and Operating Context



\* OS version and patch level

\* Domain membership and system role

\* Virtual vs physical indicators

\* Network and time configuration



\### 2. Storage and Data Layout



\* Disks, partitions, volumes, and mount points

\* Free space and growth considerations

\* Filesystem characteristics relevant to migration tools



\### 3. File Sharing and Access



\* SMB shares and configurations

\* NTFS permission structures

\* Active sessions and open files

\* DFS usage, if present



\### 4. Services and Applications



\* Installed software

\* Windows services and service accounts

\* Scheduled tasks and automation jobs

\* IIS, SQL, or print services where applicable



\### 5. Security and Access Context



\* Local administrators and groups

\* Service account usage patterns

\* Permission inheritance and explicit ACLs



\### 6. Operational Readiness Signals



\* Backup and VSS status

\* Event log indicators of instability

\* Conditions that increase migration risk



---



\## Outputs and Artifacts



A completed preflight produces a \*\*time-stamped artifact set\*\* that can be:



\* Attached to a project or change record

\* Reviewed by engineering and stakeholders

\* Used to validate post-migration parity

\* Retained as audit evidence



Artifacts should be treated as \*\*read-only records\*\* and not modified after collection.



---



\## Relationship to Migration Execution



The preflight phase directly informs:



\* Target server sizing and disk layout

\* Share recreation strategy

\* Permission migration approach

\* Cutover window planning

\* Rollback and contingency planning



No data migration should begin until preflight findings have been reviewed and acknowledged.



---



\## Related Documents



\* Data Migration Risk Checklist

\* Cutover Readiness Validation

\* Server Migration Preflight Scripts (this section’s `scripts` directory)



---





