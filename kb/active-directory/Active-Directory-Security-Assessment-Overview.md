# Active Directory Security Assessment Overview

## Purpose

This knowledge base article provides an overview of the **Active Directory (AD) security assessment framework** implemented in this repository. The goal of this assessment is to deliver **repeatable, read-only, and defensible visibility** into common Active Directory security risks without introducing operational impact.

This framework is designed for use by systems engineers, security engineers, and auditors who need **accurate, explainable findings** rather than opaque “scanner output.”

---

## Scope of the Assessment

The AD security assessment focuses on **identity, authentication, authorization, and trust boundaries** within an Active Directory environment.

The assessment evaluates the following high-risk domains:

* Privileged identity and group membership
* Delegation and Kerberos configuration
* Replication and directory control rights
* Group Policy security posture
* Certificate Services (AD CS) exposure
* Domain and forest functional levels
* Cryptographic and legacy protocol usage
* Trust relationships and boundary controls

All checks are **read-only** and rely exclusively on directory queries and security descriptor inspection.

---

## Design Principles

### 1. Read-Only by Design

All scripts are intentionally non-destructive:

* No changes to objects
* No policy enforcement
* No permission modifications
* No registry writes

This allows the assessment to be safely run in **production environments** without change control.

---

### 2. Evidence-Based Findings

Each script returns structured findings that include:

* What was detected
* Why it matters
* Supporting data (counts, samples, configuration state)

This ensures findings can be:

* Validated by engineers
* Explained to auditors
* Reviewed during incident response

---

### 3. Context-Aware Severity

Severity levels reflect **potential impact**, not automatic compromise:

* **Critical** – Likely domain compromise or Tier-0 control
* **High** – Serious misconfiguration with clear abuse paths
* **Medium** – Risky configuration requiring validation
* **Low** – Hygiene or defense-in-depth improvement
* **Info** – Visibility and inventory data
* **Warning** – Assessment limitations or missing prerequisites

Severity does not imply intent or exploitability in isolation.

---

## Assessment Categories

### Identity & Privilege

Focuses on who can do what inside the domain:

* Privileged group membership
* adminCount and AdminSDHolder behavior
* Shadow admin delegation paths
* Service account privilege exposure

### Kerberos & Authentication

Evaluates authentication pathways attackers frequently abuse:

* Unconstrained and constrained delegation
* Resource-based constrained delegation (RBCD)
* Encryption types and legacy crypto usage
* Delegatable privileged accounts

### Replication & Directory Control

Identifies control-plane risks:

* DCSync-equivalent replication rights
* Unauthorized directory control permissions
* Tier-0 object ACL exposure

### Group Policy

Analyzes configuration enforcement and drift:

* Security baseline differences
* GPO permissions
* Link order and enforcement behavior

### Certificate Services (AD CS)

Surfaces common certificate abuse risks:

* Risky certificate templates
* Issued certificate visibility
* CA configuration exposure

### Trusts & Boundaries

Examines cross-domain and cross-forest risk:

* External and forest trusts
* SID filtering
* Selective authentication
* Trust crypto posture

### Platform & Crypto Baseline

Evaluates foundational security capabilities:

* Domain and forest functional levels
* Domain controller OS distribution
* Kerberos encryption readiness

---

## How the Assessment Is Executed

The assessment is orchestrated through a central runner that:

1. Discovers available security test scripts
2. Executes each script independently
3. Aggregates findings into a unified structure
4. Supports export for reporting and review

Scripts are intentionally **loosely coupled** so they can be:

* Run individually
* Extended without breaking orchestration
* Used independently in incident response

---

## What This Assessment Does *Not* Do

This framework is not:

* A penetration test
* An exploitation toolkit
* A compliance attestation
* An automated remediation system

It does not:

* Attempt lateral movement
* Exploit misconfigurations
* Modify Active Directory objects
* Replace security monitoring or EDR

---

## Intended Use Cases

This assessment is suitable for:

* Security posture reviews
* Pre-audit preparation
* Incident response validation
* Domain migration readiness
* Technical risk documentation
* Continuous improvement tracking

---

## Next Steps

After reviewing this overview, proceed to the following KB articles to understand specific risk areas in detail:

* Privileged identity and adminCount behavior
* Shadow admin and delegation paths
* Kerberos and crypto configuration risks
* Trust and boundary security

---

