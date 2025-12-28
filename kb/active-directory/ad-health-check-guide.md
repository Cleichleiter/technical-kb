# \# Active Directory Health Check Guide

# 

# \## Purpose

# This knowledge base article provides a structured overview of how to assess the health of an Active Directory (AD) environment. It outlines critical areas to evaluate, why they matter, and common indicators of healthy versus unhealthy states.

# 

# This guide is intended to support troubleshooting, audits, migrations, and ongoing operational hygiene.

# 

# \## Overview

# Active Directory is a foundational dependency for authentication, authorization, and policy enforcement in Windows environments. Issues within AD often surface indirectly—failed logins, Group Policy inconsistencies, replication delays, or application authentication failures.

# 

# A comprehensive AD health check focuses on:

# \- Domain controller health

# \- Replication integrity

# \- DNS functionality

# \- SYSVOL consistency

# \- Time synchronization

# \- Security posture and configuration drift

# 

# Health checks should be performed regularly and always prior to:

# \- Server or domain controller migrations

# \- Forest or domain functional level changes

# \- Major application deployments

# \- Security audits or incident response

# 

# \## Scope and Applicability

# This guide applies to:

# \- Active Directory Domain Services (AD DS)

# \- Windows Server 2016 and later

# \- Single-domain and multi-domain forests

# \- On-premises and hybrid environments

# 

# This guide does \*\*not\*\* provide:

# \- Step-by-step remediation procedures

# \- Forest redesign or consolidation strategies

# \- Client-specific configurations

# 

# \## Prerequisites

# To perform or interpret an AD health check, the following are assumed:

# \- Domain or enterprise administrative access (read-only at minimum)

# \- Familiarity with core AD concepts

# \- Access to domain controllers and event logs

# \- DNS administrative visibility

# 

# \## Core Health Check Areas

# 

# \### Domain Controller Availability

# Each domain controller should:

# \- Be online and reachable

# \- Advertise itself correctly in DNS

# \- Respond to authentication requests

# \- Hold expected FSMO roles (if applicable)

# 

# Indicators of concern include:

# \- Intermittent DC availability

# \- Authentication delays

# \- Missing or stale DNS records

# 

# \### Replication Health

# Replication ensures consistency across domain controllers.

# 

# Key indicators:

# \- No persistent replication failures

# \- Acceptable replication latency

# \- No lingering objects or USN rollback events

# 

# Replication issues commonly lead to:

# \- Inconsistent Group Policy application

# \- Authentication anomalies

# \- Directory data divergence

# 

# \### DNS Health

# Active Directory is tightly coupled to DNS.

# 

# Critical DNS checks include:

# \- Correct SRV record registration

# \- DCs using only AD-integrated DNS servers

# \- No external DNS servers configured on DC NICs

# \- Forward and reverse lookup zone integrity

# 

# DNS misconfiguration is one of the most common root causes of AD instability.

# 

# \### SYSVOL and Group Policy

# SYSVOL consistency is required for Group Policy delivery.

# 

# Health indicators:

# \- SYSVOL replicated successfully across DCs

# \- No DFS-R or FRS backlogs

# \- Group Policy Objects accessible and version-consistent

# 

# SYSVOL issues typically manifest as:

# \- GPOs not applying

# \- Login script failures

# \- Inconsistent security settings

# 

# \### Time Synchronization

# Kerberos authentication is time-sensitive.

# 

# Key requirements:

# \- All domain members synchronized to domain hierarchy

# \- PDC Emulator synchronized to a reliable time source

# \- Minimal time drift across the domain

# 

# Time skew commonly causes:

# \- Authentication failures

# \- Kerberos ticket issues

# \- Application login errors

# 

# \### FSMO Roles

# FSMO roles should:

# \- Be clearly assigned

# \- Reside on healthy, stable DCs

# \- Be documented and monitored

# 

# Unhealthy FSMO placement increases risk during outages or migrations.

# 

# \### Event Logs and System Errors

# Event logs often reveal issues before they become user-visible.

# 

# Key logs to review:

# \- Directory Service

# \- DNS Server

# \- DFS Replication

# \- System

# 

# Recurring warnings or errors should be investigated, even if no active outage exists.

# 

# \## Security and Configuration Baseline

# A health check should also include:

# \- Secure LDAP configuration

# \- Disabled legacy protocols where possible

# \- Review of privileged group memberships

# \- Password and lockout policy alignment

# \- Detection of stale computer or user objects

# 

# Security drift is a common long-term AD risk.

# 

# \## Performance and Scaling Considerations

# As environments grow, additional factors matter:

# \- DC hardware sizing

# \- Site and subnet configuration accuracy

# \- Replication topology optimization

# \- Network latency between sites

# 

# Ignoring scaling factors often leads to “slow AD” symptoms rather than outright failures.

# 

# \## Risks and Caveats

# Common AD health risks include:

# \- Assuming “no alerts” means healthy

# \- Treating DNS as separate from AD

# \- Ignoring replication warnings

# \- Running migrations without a baseline health check

# \- Making changes without understanding FSMO dependencies

# 

# Preventative checks reduce emergency remediation.

# 

# \## Validation and Expected Outcomes

# A healthy AD environment typically shows:

# \- Clean replication status

# \- Stable DNS resolution

# \- Consistent SYSVOL state

# \- Minimal AD-related event log noise

# \- Predictable authentication behavior

# 

# Health check results should be documented and retained for comparison over time.

# 

# \## Related SOPs and KBs

# \- kb/active-directory/fsmo-roles-explained.md

# \- sop/server-migration/pre-migration-checklist.md

# \- sop/server-migration/post-migration-validation.md

# 

# \## References

# \- Microsoft Active Directory troubleshooting documentation

# \- Windows Server AD DS architecture documentation

# \- Microsoft best practices for AD DNS integration



