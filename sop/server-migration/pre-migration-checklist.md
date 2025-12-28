# \# Pre-Migration Checklist Procedure

# 

# \## Purpose

# This Standard Operating Procedure (SOP) defines the required validation and preparation steps that must be completed \*\*before initiating a server or workload migration\*\*. Its purpose is to reduce risk, prevent data loss, and ensure the environment is in a known-good state prior to change.

# 

# A migration should \*\*not proceed\*\* until all checklist items are reviewed and validated.

# 

# \## Scope

# This SOP applies to:

# \- Windows server migrations

# \- File server migrations

# \- Application server migrations

# \- On-premises, virtualized, and hybrid environments

# 

# This SOP does \*\*not\*\* cover:

# \- Migration execution steps

# \- Post-migration validation

# \- Client-specific business acceptance testing

# 

# \## Roles and Responsibilities

# \- \*\*Executor\*\*: Performs checklist validation and records findings

# \- \*\*Reviewer\*\*: Confirms readiness and authorizes migration

# \- \*\*Stakeholder\*\*: Approves migration timing and impact, if required

# 

# \## Preconditions and Prerequisites

# Before beginning this checklist:

# \- Migration scope and target systems are defined

# \- Maintenance window is approved

# \- Change record or ticket is created and approved

# \- Access to source and destination systems is confirmed

# 

# \## Inputs and Dependencies

# This SOP depends on:

# \- Source system details (OS, roles, applications)

# \- Destination system design or build documentation

# \- Network, identity, and storage dependencies

# \- Relevant KB articles for validation context

# 

# \## Procedure

# 

# \### 1. Scope and Inventory Confirmation

# 1\. Confirm the systems included in the migration.

# 2\. Identify server roles and installed applications.

# 3\. Document data locations, volumes, and shares.

# 4\. Identify dependent systems and integrations.

# 

# \### 2. Active Directory and Identity Health

# If the system is domain-joined:

# 1\. Validate Active Directory health.

# 2\. Confirm domain controller availability and replication health.

# 3\. Verify DNS configuration and resolution.

# 4\. Confirm Group Policy processing on the source system.

# 

# Any unresolved AD issues must be addressed before migration.

# 

# \### 3. System Health and Stability

# 1\. Review system event logs for recurring errors or warnings.

# 2\. Confirm system uptime and stability.

# 3\. Validate disk health, free space, and file system integrity.

# 4\. Confirm no pending reboots or failed updates.

# 

# Unstable systems should not be migrated.

# 

# \### 4. Application Readiness

# 1\. Identify all applications and services hosted on the system.

# 2\. Confirm application versions and support status.

# 3\. Identify application-specific migration requirements.

# 4\. Verify service accounts, credentials, and dependencies.

# 

# \### 5. Data Readiness and Integrity

# 1\. Confirm data volumes and directories to be migrated.

# 2\. Validate permissions, ownership, and inheritance.

# 3\. Identify open-file or locked-file scenarios.

# 4\. Determine whether application-consistent snapshots are required.

# 

# \### 6. Backup and Recovery Validation

# 1\. Confirm recent successful backups exist.

# 2\. Validate backup scope includes all required data.

# 3\. Confirm restore procedures are documented and tested if required.

# 4\. Ensure backup retention meets policy requirements.

# 

# Migration must not proceed without a valid recovery path.

# 

# \### 7. Network and Connectivity Readiness

# 1\. Confirm destination network configuration.

# 2\. Validate firewall rules and required ports.

# 3\. Confirm DNS records and name resolution expectations.

# 4\. Identify IP address changes or routing updates.

# 

# \### 8. Security and Compliance Review

# 1\. Review endpoint protection status.

# 2\. Validate patch and vulnerability posture.

# 3\. Confirm least-privilege access models.

# 4\. Identify any regulatory or compliance considerations.

# 

# \### 9. Migration Method Validation

# 1\. Confirm migration tooling and approach (e.g., Robocopy, VSS-based copy).

# 2\. Validate performance and impact expectations.

# 3\. Confirm logging and validation mechanisms.

# 4\. Perform test runs where feasible.

# 

# \### 10. Communication and Change Readiness

# 1\. Confirm maintenance window and outage expectations.

# 2\. Notify stakeholders of migration timing.

# 3\. Define rollback decision points.

# 4\. Confirm on-call or escalation coverage.

# 

# \## Validation and Readiness Criteria

# The migration is considered ready when:

# \- All checklist sections are reviewed

# \- No blocking issues remain

# \- Backups are confirmed

# \- Stakeholders approve proceeding

# \- Rollback plan is documented

# 

# Checklist results must be documented in the migration record.

# 

# \## Rollback and Recovery Planning

# Prior to migration:

# \- Identify rollback trigger conditions

# \- Confirm restore points or snapshots

# \- Document rollback ownership and steps

# \- Ensure rollback can be executed within acceptable timeframes

# 

# \## Error Handling and Escalation

# Escalate and pause migration if:

# \- Backup validation fails

# \- Active Directory health issues are detected

# \- Application dependencies are unclear

# \- Security posture is insufficient

# 

# Do not proceed under uncertainty.

# 

# \## Logging and Audit Trail

# Maintain records of:

# \- Checklist completion

# \- Identified risks and mitigations

# \- Approval to proceed

# \- Date and time of validation

# 

# These records support audit, compliance, and post-incident review.

# 

# \## Post-Execution Tasks

# After checklist completion:

# \- Confirm migration go/no-go decision

# \- Finalize migration schedule

# \- Lock change scope

# \- Prepare post-migration validation steps

# 

# \## Related KBs and SOPs

# \- kb/active-directory/ad-health-check-guide.md

# \- kb/windows/robocopy-multithreaded-file-replication.md

# \- kb/windows/vss-snapshot-basics.md

# \- kb/backup-recovery/robocopy-vs-vss.md

# \- sop/server-migration/post-migration-validation.md

# 

# \## Notes and Assumptions

# This SOP assumes:

# \- Standard enterprise security baselines

# \- Adequate monitoring and backup tooling

# \- Change management processes are enforced

# 

