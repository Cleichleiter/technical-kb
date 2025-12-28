# Data Migration Risk Checklist

## Purpose

This knowledge base article provides a **risk-focused checklist** used to evaluate findings from the server migration preflight process and determine whether a data migration is ready to proceed.

The checklist translates discovery data into **actionable decision points**, helping engineers identify conditions that increase the likelihood of migration failure, data inconsistency, extended downtime, or post-cutover remediation.

This document is intended to be reviewed **after preflight data collection** and **before migration execution**.

---

## How to Use This Checklist

* Review each section using the artifacts generated during the preflight phase
* Mark each item as:

  * Addressed
  * Accepted Risk
  * Requires Remediation
* Do not proceed with migration until all **High Risk** items are either resolved or formally accepted

This checklist does not replace engineering judgment; it exists to ensure known risk patterns are not overlooked.

---

## High-Risk Conditions (Migration Blockers)

These conditions should be resolved before migration unless there is explicit approval and rollback coverage.

### Storage and Data Layout

* Volumes or mount points not accounted for in target sizing
* Insufficient free space on source or target to support migration overhead
* Unsupported filesystem features or incompatible allocation unit sizes
* Excessive long-path usage that may exceed tool or OS limits

### Permissions and Access

* NTFS permissions with heavy reliance on explicit ACEs without inheritance
* Unknown or orphaned SIDs present on critical data paths
* Share permissions that conflict with NTFS permissions
* Service accounts with undocumented access requirements

### File Locking and Active Use

* Persistent open files or long-lived SMB sessions
* Applications writing continuously to data paths without a quiescence plan
* No defined maintenance or cutover window

### Backup and Recovery

* No recent successful backup of source data
* VSS writers in a failed or unstable state
* No documented rollback plan

---

## Medium-Risk Conditions (Mitigation Required)

These conditions do not block migration outright but require planning and validation.

### Services and Applications

* Windows services or scheduled tasks running under local or legacy accounts
* Applications installed locally but storing data in shared paths
* Hard-coded paths or server names discovered in configurations

### Operational Signals

* Repeated warnings or errors in event logs related to disk, SMB, or authentication
* High disk latency or performance instability during peak usage
* Inconsistent patching or outdated OS builds

### Share and Namespace Design

* DFS namespaces with complex referral ordering
* Shares with mixed use cases (user data and application data combined)
* Legacy share naming conventions that conflict with new standards

---

## Low-Risk / Informational Findings

These findings should be documented but typically do not require remediation.

* Inactive shares with no recent access
* Disabled scheduled tasks
* Redundant or obsolete data sets approved for decommissioning
* Software identified for retirement post-migration

---

## Risk Acceptance and Documentation

Any unresolved risk must be:

* Clearly documented
* Reviewed by the responsible technical owner
* Accepted with awareness of potential impact

Risk acceptance does not eliminate responsibility; it establishes intent and awareness.

---

## Output Expectations

Completion of this checklist should result in:

* A clear go/no-go decision for migration
* A defined remediation list, if required
* Alignment between engineering, stakeholders, and project owners

This checklist should be retained alongside preflight artifacts for auditability and future reference.

---

## Related Documents

* Server Migration Preflight Overview
* Cutover Readiness Validation
* Server Migration Preflight Scripts

---


