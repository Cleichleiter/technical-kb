\## \*\*KB #6: Active Directory Trusts and Boundary Security Explained\*\*



Below is \*\*KB #6\*\*, written in the \*\*exact same style\*\* you approved (no code blocks, clean Markdown, GitHub-friendly).



---



\# Active Directory Trusts and Boundary Security Explained



\## Purpose



This knowledge base article explains \*\*Active Directory trust relationships\*\*, why they represent \*\*security boundaries\*\*, and how misconfigured trusts can dramatically expand an attacker’s blast radius.



Trusts are often created to solve legitimate business problems, but they are frequently \*\*under-documented, poorly reviewed, and implicitly trusted\*\* long after their original purpose fades.



---



\## What Is an Active Directory Trust?



An Active Directory trust allows identities in one domain or forest to authenticate to resources in another.



At a high level, a trust answers the question:



> “Should this domain accept identities issued somewhere else?”



Trusts are foundational to:



\* Mergers and acquisitions

\* Multi-forest environments

\* Legacy domain coexistence

\* Partner access scenarios



They are also one of the \*\*most misunderstood\*\* security constructs in AD.



---



\## Why Trusts Are Security Boundaries



A trust is not just a connectivity feature—it is a \*\*security boundary decision\*\*.



When a trust exists, you are implicitly deciding:



\* Which identities are accepted

\* What authentication methods are allowed

\* How much of the foreign directory is trusted

\* Whether compromise can propagate across environments



Poorly controlled trusts allow attackers to:



\* Move laterally between domains

\* Escalate privileges across forests

\* Abuse legacy authentication paths

\* Bypass segmentation assumptions



---



\## Common Trust Types



\### External Trusts



Used to connect two separate domains.



Characteristics:



\* Often legacy

\* Frequently long-lived

\* Common in older environments



Risk Consideration:

External trusts are often created quickly and reviewed rarely.



---



\### Forest Trusts



Used to connect entire forests.



Characteristics:



\* Broader trust scope

\* Enables transitive authentication

\* Often created during M\&A activity



Risk Consideration:

Forest trusts dramatically expand blast radius if not tightly scoped.



---



\## Transitive vs. Non-Transitive Trusts



\*\*Transitive trusts\*\* extend trust beyond the immediate domain.



\*\*Non-transitive trusts\*\* restrict trust to the explicitly defined boundary.



Transitivity increases convenience—but also increases risk.



---



\## SID Filtering and Why It Matters



SID filtering protects against \*\*SIDHistory abuse\*\*, where attackers inject privileged SIDs from one domain into another.



Without SID filtering:



\* Foreign identities may inherit unintended privileges

\* Trust boundaries become porous

\* Cross-domain escalation becomes possible



SID filtering should be enabled on \*\*all external trusts\*\* unless there is a documented, validated reason not to.



---



\## Selective Authentication



Selective authentication restricts which principals can authenticate across a trust.



Instead of “everyone is allowed,” access must be explicitly granted.



Benefits include:



\* Reduced attack surface

\* Clear authorization intent

\* Improved auditability



Trusts without selective authentication often assume \*\*far more trust than intended\*\*.



---



\## Trust Authentication and Crypto Risks



Trust security is also influenced by:



\* Kerberos encryption types

\* Legacy authentication allowances

\* Domain functional levels

\* DC OS compatibility



A trust that relies on weak cryptography weakens both sides of the boundary.



---



\## Common Trust Misconfigurations



High-risk trust patterns include:



\* Trusts that no one remembers creating

\* Forest trusts without selective authentication

\* External trusts without SID filtering

\* Trusts using legacy crypto or NTLM

\* Trusts treated as “internal” without justification



These issues often persist unnoticed for years.



---



\## How Trusts Are Assessed



The scripts in this repository evaluate:



\* Trust type and direction

\* Transitivity behavior

\* SID filtering configuration

\* Selective authentication usage

\* Trust authentication posture



All checks are \*\*read-only\*\* and designed to surface reviewable evidence.



---



\## Interpreting Trust Findings



Trust-related findings are commonly rated:



\* \*\*High\*\*



&nbsp; \* Broad, transitive trusts with weak boundary controls

&nbsp; \* Trusts lacking SID filtering or selective authentication



\* \*\*Medium\*\*



&nbsp; \* Contextual trust configurations requiring validation



\* \*\*Info\*\*



&nbsp; \* Trust inventory and visibility data



High severity does not mean “remove immediately”—it means \*\*review deliberately\*\*.



---



\## Remediation Guidance



When trust risks are identified:



1\. Confirm the business purpose of the trust

2\. Validate who actually needs cross-domain access

3\. Enable SID filtering where possible

4\. Implement selective authentication

5\. Reduce trust scope aggressively

6\. Document intent and ownership



Trusts should be treated as \*\*living security decisions\*\*, not permanent infrastructure.



---



\## Common Misconceptions



\*\*“It’s an internal trust, so it’s safe.”\*\*

Internal does not mean low risk.



\*\*“We’ve always had that trust.”\*\*

Longevity does not equal legitimacy.



\*\*“Trusts don’t matter unless breached.”\*\*

Trusts define how far breaches spread.



---



\## Risk Perspective



Trusts define how compromise propagates.



A single weak trust can quietly convert \*\*one incident\*\* into \*\*many\*\*.



---



