Interpreting Active Directory Security Findings and Severity Levels

Purpose



This knowledge base article explains how to interpret security findings produced by the Active Directory security assessment framework and how to apply severity ratings correctly.



Severity levels in this repository reflect technical risk and potential impact, not immediate exploitability or incident status. Understanding this distinction is critical to using assessment results responsibly and effectively.



Severity Intent vs. Urgency



Severity indicates what could happen if a condition is abused.

Urgency reflects how quickly action is required based on context.



These are not the same.



A finding can be:



High severity but low urgency (e.g., a risky trust that is inactive)



Medium severity but high urgency (e.g., misconfiguration during an active incident)



Low severity but strategic (e.g., hygiene improvements that reduce future risk)



Severity helps you prioritize attention; urgency determines response timing.



Severity Definitions

Critical



Definition:

A configuration or condition that provides direct or near-direct Tier-0 compromise potential.



Characteristics:



Minimal attacker prerequisites



Broad or complete domain impact



Commonly abused in real-world attacks



Examples:



Non-standard principals with DCSync rights



Unconstrained delegation on privileged systems



Shadow admin ACLs on Tier-0 objects



Expected Response:



Immediate validation



Rapid remediation or containment



Executive awareness if confirmed



High



Definition:

A serious misconfiguration that creates a clear exploitation path under realistic conditions.



Characteristics:



Requires some attacker positioning



Can lead to privilege escalation or lateral movement



Often chained with other weaknesses



Examples:



Privileged service accounts with delegation enabled



DES-enabled Kerberos encryption



Risky AD CS templates



Expected Response:



Prompt review and remediation planning



Risk acceptance only with documented justification



Medium



Definition:

A configuration that increases attack surface or weakens security posture but may require multiple conditions to exploit.



Characteristics:



Context-dependent risk



Often environment- or use-case-specific



May be legitimate but should be documented



Examples:



Constrained delegation configurations



RC4-only Kerberos encryption



External trusts with weak boundary controls



Expected Response:



Validate business need



Reduce scope or harden where feasible



Track as part of security backlog



Low



Definition:

A hygiene or defense-in-depth improvement that reduces future risk but is unlikely to be directly exploitable on its own.



Characteristics:



Improves resilience and clarity



Often accumulates risk over time if ignored



Common in long-lived environments



Examples:



Inactive privileged accounts



Privileged users not in Protected Users



Legacy functional levels without immediate exposure



Expected Response:



Schedule remediation during normal maintenance



Address opportunistically during other changes



Info



Definition:

Visibility or inventory information with no implied risk judgment.



Characteristics:



Provides context for other findings



Useful for audits and baselines



Often referenced in discussions, not actions



Examples:



Privileged group membership counts



Domain controller OS distribution



Trust inventory listings



Expected Response:



Review for awareness



Use as supporting data



Warning



Definition:

Indicates assessment limitations or missing prerequisites, not a security finding.



Characteristics:



Script could not complete fully



Required module or permission missing



Partial visibility only



Examples:



ActiveDirectory module not available



Insufficient rights to read ACLs



Expected Response:



Re-run assessment with proper permissions



Document scope limitations if unresolved



Environmental vs. Exploitable Risk



Not all findings represent active exploitation.



This framework distinguishes between:



Environmental risk

A condition that weakens security posture but may be controlled by other factors (process, monitoring, isolation).



Exploitable risk

A condition that can be realistically abused given common attacker access patterns.



For example:



An external trust may be high risk in one environment and acceptable in another.



Delegation on a hardened Tier-0 system is different from delegation on a general-purpose server.



Context matters.



Why Some High Findings Are Contextual



Certain areas—especially trusts and delegation—are inherently contextual.



A finding may be marked High because:



It has historically high abuse potential



It expands blast radius significantly



It bypasses traditional security boundaries



This does not mean:



The configuration is automatically wrong



It must be removed without review



Instead, it signals:



“This configuration deserves careful validation, documentation, and ongoing oversight.”



Remediation Prioritization Guidance



When reviewing findings, prioritize in this order:



Critical + Confirmed

Immediate action



High + Unjustified

Plan remediation quickly



Medium + Poorly Understood

Investigate and document



Low + Accumulative

Schedule hygiene improvements



Info

Use for context and reporting



Avoid “severity panic.”

The goal is risk reduction, not chasing zero findings.



Using Findings in Practice



Security findings should be used to:



Drive informed engineering decisions



Support audit readiness



Document accepted risk



Track improvement over time



They should not be used as:



A blame mechanism



A replacement for incident response



A substitute for threat modeling

