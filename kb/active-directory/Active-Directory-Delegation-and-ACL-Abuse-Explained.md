# Active Directory Delegation and ACL Abuse Explained

## Purpose

This knowledge base article explains **Active Directory delegation**, how permissions are implemented through **Access Control Lists (ACLs)**, and why misconfigured delegation is one of the **most common and dangerous privilege escalation paths** in Active Directory.

Delegation is often introduced to enable operational efficiency, but over time it becomes **opaque, over-scoped, and poorly audited**, creating silent administrative backdoors.

---

## What Is Delegation in Active Directory?

Delegation allows non-administrative users or groups to perform **specific actions** within Active Directory without granting full administrative roles.

Delegation is implemented through:

* Access Control Entries (ACEs)
* Applied to directory objects (users, groups, OUs, computers)
* Stored in Access Control Lists (ACLs)

At a fundamental level, delegation answers the question:

> “Who is allowed to do what to this object?”

---

## Why Delegation Is a Security Boundary

Delegation is not merely a convenience mechanism. It represents a **privilege boundary decision**.

When delegation is applied, you are deciding:

* Who can modify identities
* Who can reset passwords
* Who can change group membership
* Who can control authentication-related attributes

Improper delegation enables attackers to:

* Escalate privileges without exploiting vulnerabilities
* Create or modify high-impact accounts
* Persist access invisibly
* Bypass administrative role separation

Many AD compromises rely on **delegation abuse**, not malware.

---

## Understanding ACLs and ACEs

### Access Control Lists (ACLs)

An ACL is a list of permissions applied to an AD object.

Each ACL contains multiple **Access Control Entries (ACEs)**.

---

### Access Control Entries (ACEs)

An ACE defines:

* **Who** (user or group)
* **What** (specific permission or right)
* **Where** (which object or attribute)
* **How** (allow or deny)

Multiple ACEs can apply to the same object, often inherited from parent containers.

---

## Common Delegation Use Cases

Delegation is frequently used for:

* Help desk password resets
* User account creation and deprovisioning
* Group membership management
* Computer account administration
* Application service account control

These use cases are valid—but only when **tightly scoped and documented**.

---

## High-Risk Delegation Permissions

Certain permissions are especially dangerous:

* Resetting passwords on privileged users
* Modifying group membership
* Writing to `servicePrincipalName`
* Writing to `msDS-KeyCredentialLink`
* GenericAll or GenericWrite on user or group objects
* Control over OUs containing privileged accounts

These permissions can allow **direct or indirect domain compromise**.

---

## Delegation vs. Role-Based Administration

Active Directory does not enforce true role-based access control.

Instead, it relies on:

* Distributed ACLs
* Inheritance
* Historical configuration decisions

This makes delegation:

* Difficult to reason about
* Easy to misconfigure
* Hard to audit without tooling

Permissions often exist **because they were once needed**, not because they still are.

---

## Inheritance and Privilege Creep

Delegation commonly becomes dangerous due to inheritance.

Examples include:

* OU-level permissions applying to newly created objects
* Delegation applied broadly “for future growth”
* Privileged accounts accidentally placed in delegated containers

Inheritance allows risk to **expand silently over time**.

---

## Common Delegation Misconfigurations

High-risk patterns include:

* GenericAll permissions on user or group objects
* Delegation applied directly to privileged groups
* Help desk groups with excessive rights
* Delegation without documented scope or purpose
* Permissions granted to users instead of groups
* Legacy permissions that no one owns

These issues rarely generate alerts and often persist indefinitely.

---

## How Delegation Is Assessed

The scripts in this repository evaluate:

* Non-standard ACLs on directory objects
* High-risk permission combinations
* Delegation applied to privileged objects
* Inheritance paths that amplify impact
* Principals with effective administrative control

All checks are **read-only** and focused on surfacing reviewable evidence.

---

## Interpreting Delegation Findings

Delegation-related findings are commonly rated:

**High Severity**

* Effective control over privileged users or groups
* GenericAll or GenericWrite on sensitive objects
* Ability to modify authentication-related attributes

**Medium Severity**

* Broad delegation that exceeds stated purpose
* Delegation requiring scope validation

**Informational**

* Delegation inventory and visibility findings

High severity indicates **structural privilege risk**, not necessarily active abuse.

---

## Remediation Guidance

When risky delegation is identified:

1. Identify the business justification
2. Confirm the minimum required permissions
3. Replace broad rights with attribute-level permissions
4. Remove delegation from privileged objects
5. Use groups, not users, for delegation
6. Document ownership and review cadence

Delegation should be **intentional, minimal, and reviewable**.

---

## Common Misconceptions

**“Delegation isn’t admin access.”**
Delegation can be equivalent—or worse—than admin access.

**“That group just does help desk work.”**
Help desk permissions frequently enable privilege escalation.

**“ACLs are too complex to fix.”**
Complexity does not reduce risk.

---

## Risk Perspective

Delegation defines **who can become powerful without detection**.

Attackers do not need exploits when delegation gives them permission.

---


