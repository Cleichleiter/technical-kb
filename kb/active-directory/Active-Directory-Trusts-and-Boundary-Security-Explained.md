# Active Directory Trusts and Boundary Security

## Purpose

This knowledge base article explains **Active Directory trust relationships**, why they function as **security boundaries**, and how misconfigured trusts can significantly expand an attacker’s blast radius.

Trusts are often implemented to solve legitimate business requirements, but they are frequently **under-documented, insufficiently reviewed, and implicitly trusted** long after their original purpose has faded.

---

## What Is an Active Directory Trust?

An Active Directory trust allows identities from one domain or forest to authenticate to resources in another.

At its core, a trust answers a single question:

> “Should this domain accept identities issued by another directory?”

Trusts are commonly used to support:

* Mergers and acquisitions
* Multi-forest architectures
* Legacy domain coexistence
* Partner or vendor access scenarios

Despite their importance, trusts are among the **most misunderstood security constructs** in Active Directory.

---

## Why Trusts Are Security Boundaries

A trust is not merely a connectivity feature. It represents a **security boundary decision**.

When a trust exists, the organization is implicitly deciding:

* Which external identities are accepted
* What authentication methods are permitted
* How much of a foreign directory is trusted
* Whether compromise can propagate across environments

Poorly controlled trusts can allow attackers to:

* Move laterally between domains
* Escalate privileges across forests
* Abuse legacy authentication paths
* Bypass assumed network or identity segmentation

---

## Common Trust Types

### External Trusts

External trusts connect individual domains.

**Characteristics**

* Often legacy in nature
* Frequently long-lived
* Common in older or transitional environments

**Risk Consideration**

External trusts are commonly created quickly and reviewed infrequently, making them high-risk over time.

---

### Forest Trusts

Forest trusts connect entire Active Directory forests.

**Characteristics**

* Broad trust scope
* Transitive authentication by default
* Common during mergers and acquisitions

**Risk Consideration**

Forest trusts can dramatically expand an attacker’s blast radius if boundary controls are not tightly enforced.

---

## Transitive vs. Non-Transitive Trusts

* **Transitive trusts** extend trust beyond the immediately connected domain.
* **Non-transitive trusts** restrict trust strictly to the defined boundary.

Transitivity increases convenience, but it also **amplifies risk** by extending authentication paths.

---

## SID Filtering and Why It Matters

SID filtering protects against **SIDHistory abuse**, where attackers inject privileged SIDs from one domain into another.

Without SID filtering:

* Foreign identities may inherit unintended privileges
* Trust boundaries become porous
* Cross-domain privilege escalation becomes possible

SID filtering should be enabled on **all external trusts** unless a documented and validated exception exists.

---

## Selective Authentication

Selective authentication restricts which principals are allowed to authenticate across a trust.

Instead of permitting broad access, authentication rights must be explicitly granted.

**Benefits include**

* Reduced attack surface
* Clear authorization intent
* Improved auditability

Trusts without selective authentication often assume **far more trust than was ever intended**.

---

## Trust Authentication and Cryptographic Risk

Trust security is also influenced by:

* Kerberos encryption types
* Legacy authentication allowances
* Domain and forest functional levels
* Domain controller operating system compatibility

A trust that relies on weak cryptography weakens **both sides of the boundary**.

---

## Common Trust Misconfigurations

High-risk trust patterns include:

* Trusts no one remembers creating
* Forest trusts without selective authentication
* External trusts without SID filtering
* Trusts allowing NTLM or weak cryptography
* Trusts treated as “internal” without justification

These conditions often persist unnoticed for years.

---

## How Trusts Are Assessed

The scripts in this repository evaluate:

* Trust type and direction
* Transitivity behavior
* SID filtering configuration
* Selective authentication usage
* Trust authentication posture

All checks are **read-only** and designed to surface reviewable evidence.

---

## Interpreting Trust Findings

Trust-related findings are commonly rated as:

**High Severity**

* Broad, transitive trusts with weak boundary controls
* Trusts lacking SID filtering or selective authentication

**Medium Severity**

* Context-dependent trust configurations requiring validation

**Informational**

* Trust inventory and visibility findings

High severity does not imply immediate removal. It indicates the need to **review deliberately and intentionally**.

---

## Remediation Guidance

When trust risks are identified:

1. Confirm the original and current business purpose
2. Validate who actually requires cross-domain access
3. Enable SID filtering where feasible
4. Implement selective authentication
5. Aggressively reduce trust scope
6. Document ownership, intent, and review cadence

Trusts should be treated as **living security decisions**, not permanent infrastructure.

---

## Common Misconceptions

**“It’s an internal trust, so it’s safe.”**
Internal does not equate to low risk.

**“We’ve always had that trust.”**
Longevity does not establish legitimacy.

**“Trusts don’t matter unless we’re breached.”**
Trusts define how far a breach can spread.

---

## Risk Perspective

Trusts determine how compromise propagates.

A single weak trust can quietly transform **one incident** into **many**.

---
