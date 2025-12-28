# \# User Offboarding Procedure

# 

# \## Purpose

# This Standard Operating Procedure (SOP) defines the required steps to securely and consistently offboard a user from organizational systems. The objective is to immediately remove access, preserve required data, reduce security risk, and maintain an auditable record of the offboarding event.

# 

# User offboarding is a \*\*security control\*\*, not an administrative task, and must be executed with precision and documentation.

# 

# \## Scope

# This SOP applies to:

# \- Employees, contractors, and temporary users

# \- Voluntary and involuntary separations

# \- On-premises, cloud, and hybrid environments

# \- Identity, endpoint, application, and data access

# 

# This SOP does \*\*not\*\* cover:

# \- HR policy decisions

# \- Legal or disciplinary processes

# \- Client-specific contractual requirements (unless referenced separately)

# 

# \## Roles and Responsibilities

# \- \*\*Requestor (HR / Management)\*\*: Initiates offboarding request and confirms timing

# \- \*\*Executor (IT / Systems Administrator)\*\*: Performs technical offboarding steps

# \- \*\*Reviewer (IT Lead / Security)\*\*: Verifies completion and approves closure

# 

# \## Preconditions and Prerequisites

# Before execution:

# \- Offboarding request is approved and documented

# \- Effective date and time are confirmed

# \- User identity is clearly identified (UPN, username, email)

# \- Manager and data ownership are identified

# \- Ticket or change record exists

# 

# For involuntary terminations, this SOP must be executed \*\*immediately\*\* at the approved time.

# 

# \## Inputs and Dependencies

# This SOP depends on:

# \- Identity provider(s) (e.g., Active Directory, Azure AD)

# \- Endpoint management platforms

# \- Application and SaaS inventories

# \- Backup and retention policies

# \- Relevant KB articles for identity and access systems

# 

# \## Procedure

# 

# \### 1. Identity and Authentication Revocation

# 1\. Disable the user account in the primary identity provider.

# 2\. Block cloud sign-in and revoke active sessions.

# 3\. Reset credentials to a random, non-recoverable value.

# 4\. Invalidate refresh tokens and authentication caches.

# 5\. Confirm the account cannot authenticate.

# 

# Identity revocation must be treated as the \*\*first and highest priority step\*\*.

# 

# \### 2. Privileged Access Removal

# 1\. Remove user from all privileged or administrative groups.

# 2\. Review and remove delegated permissions.

# 3\. Revoke access to shared or service accounts.

# 4\. Document any non-standard privilege assignments.

# 

# Privileged access must not persist after offboarding.

# 

# \### 3. Endpoint and Device Access

# 1\. Disable or remove device login access.

# 2\. Trigger device lock, sign-out, or wipe if required.

# 3\. Remove user profiles from shared systems where appropriate.

# 4\. Recover or document disposition of assigned hardware.

# 

# Lost or unmanaged devices must be escalated immediately.

# 

# \### 4. Application and SaaS Access

# 1\. Revoke access to all known applications and SaaS platforms.

# 2\. Remove user licenses where appropriate.

# 3\. Transfer ownership of application resources as needed.

# 4\. Validate access revocation for high-risk systems.

# 

# Do not assume identity disablement removes all application access.

# 

# \### 5. Data Preservation and Ownership Transfer

# 1\. Preserve mailbox, files, and collaboration data per policy.

# 2\. Transfer data ownership to the designated manager or team.

# 3\. Apply retention or legal hold requirements if applicable.

# 4\. Restrict user access to preserved data.

# 

# Data handling must comply with retention and privacy requirements.

# 

# \### 6. Group Membership and Permissions Review

# 1\. Remove user from security and distribution groups.

# 2\. Review shared folder and application permissions.

# 3\. Confirm no orphaned access remains.

# 4\. Document any exceptions or delays.

# 

# \### 7. Monitoring and Alert Review

# 1\. Review recent authentication and access logs.

# 2\. Confirm no post-offboarding access attempts succeed.

# 3\. Validate monitoring coverage remains intact.

# 4\. Escalate anomalies immediately.

# 

# Post-offboarding activity may indicate credential compromise.

# 

# \### 8. Documentation and Verification

# 1\. Record all actions taken in the offboarding ticket.

# 2\. Capture timestamps for access revocation.

# 3\. Attach validation evidence where applicable.

# 4\. Obtain reviewer approval.

# 

# Offboarding is not complete until verification is documented.

# 

# \## Validation and Verification

# Offboarding is considered complete when:

# \- The user cannot authenticate to any system

# \- All privileged access is removed

# \- Devices and applications are secured

# \- Data ownership is transferred or preserved

# \- Documentation is complete and approved

# 

# \## Rollback and Recovery

# Rollback is generally \*\*not applicable\*\* to offboarding.

# 

# If access must be restored:

# \- A new access request must be approved

# \- Access must be re-provisioned explicitly

# \- Restoration must be documented as a new event

# 

# \## Error Handling and Escalation

# Escalate immediately if:

# \- Identity disablement fails

# \- Privileged access cannot be confirmed

# \- Application access cannot be revoked

# \- Suspicious activity is detected

# 

# Incomplete offboarding represents a security risk.

# 

# \## Logging and Audit Trail

# Maintain records of:

# \- Offboarding request and approval

# \- Access revocation timestamps

# \- Systems and applications affected

# \- Verification and reviewer sign-off

# 

# These records support audits, investigations, and compliance requirements.

# 

# \## Post-Execution Tasks

# After successful offboarding:

# \- Confirm closure with HR or management

# \- Schedule data retention or deletion actions

# \- Update access inventories if required

# \- Close ticket with documented approval

# 

# \## Related KBs and SOPs

# \- sop/user-lifecycle/user-onboarding-procedure.md (if applicable)

# \- kb/active-directory/ad-health-check-guide.md

# \- kb/cloud/azure-ad-connect-overview.md

# 

# \## Notes and Assumptions

# This SOP assumes:

# \- Centralized identity management

# \- Accurate application inventory

# \- Enforced change management processes

# 

