\# DCSync Attacks and Replication Rights in Active Directory



\## Purpose



This knowledge base article explains \*\*DCSync-style attacks\*\* and why \*\*directory replication rights\*\* represent one of the most severe security risks in Active Directory.



Replication rights are powerful, rarely reviewed, and frequently misunderstood. Misuse of these rights allows an attacker to \*\*extract password hashes for any account in the domain\*\*, including Domain Admins, without touching a domain controller directly.



---



\## What Is DCSync?



\*\*DCSync\*\* is an attack technique where an attacker impersonates a domain controller and requests directory replication data.



Because replication is a legitimate Active Directory function, the attack:



\- Uses standard directory protocols  

\- Does not require code execution on a domain controller  

\- Often bypasses endpoint detection  

\- Can succeed with only directory-level permissions  



If successful, the attacker can retrieve:



\- NTLM password hashes  

\- Kerberos keys  

\- Password history  

\- Secrets for all domain accounts  



At that point, the domain is \*\*effectively compromised\*\*.



---



\## Why Replication Rights Are Tier-0



Active Directory replication is part of the \*\*control plane\*\* of the directory.



Any principal with replication rights can:



\- Read sensitive credential material  

\- Bypass account protections  

\- Compromise privileged accounts silently  

\- Persist long-term access  



This is why replication permissions are considered \*\*Tier-0 equivalent\*\*, regardless of group membership.



---



\## Replication Rights Used in DCSync



DCSync relies on the following \*\*extended rights\*\* on the domain root object:



\- `DS-Replication-Get-Changes`  

\- `DS-Replication-Get-Changes-All`  

\- `DS-Replication-Get-Changes-In-Filtered-Set`  



Granting all three enables \*\*full directory replication capability\*\*.



These rights are evaluated through \*\*ACLs\*\*, not group membership alone.



---



\## Common Legitimate Holders



In most environments, these rights are expected only for:



\- Domain Controllers  

\- Domain Admins  

\- Enterprise Admins  

\- The SYSTEM account  



Any \*\*additional principals\*\* should be treated as suspicious until proven otherwise.



---



\## How DCSync Is Commonly Abused



Replication rights are often exposed through:



\- Accidental ACL delegation on the domain root  

\- Legacy permissions from migrations  

\- Misconfigured service accounts  

\- Overly broad delegation for “read access”  

\- Third-party tools granted excessive rights  



Attackers frequently target:



\- Backup operators  

\- Monitoring service accounts  

\- Old admin groups  

\- Delegated IT roles  



---



\## Why Group Membership Is Not Enough



A user does \*\*not\*\* need to be:



\- Domain Admin  

\- Enterprise Admin  

\- Local administrator on a domain controller  



They only need the \*\*replication rights\*\*.



This makes DCSync especially dangerous in environments where:



\- Privileged groups are well-controlled  

\- ACLs are not regularly audited  

\- Delegation has accumulated over time  



---



\## How Replication Rights Are Assessed



The scripts in this repository:



\- Inspect the domain root ACL  

\- Identify principals with replication extended rights  

\- Flag non-standard or unexpected trustees  

\- Distinguish inherited vs explicit permissions  



The assessment is:



\- Read-only  

\- Non-destructive  

\- Focused on evidence, not assumptions  



---



\## Interpreting Findings



Replication findings are typically rated as follows:



\### Critical

\- Non-standard principals with full replication rights



\### High

\- Delegated replication rights without clear justification



\### Info

\- Inventory of expected replication holders



Any \*\*unexpected replication access\*\* should be treated as a priority review item.



---



\## Remediation Guidance



When non-standard replication rights are identified:



1\. Identify why the permission exists  

2\. Validate whether the account still requires it  

3\. Remove unnecessary replication rights  

4\. Replace with least-privilege alternatives where possible  

5\. Document all approved exceptions  

6\. Monitor changes to the domain root ACL going forward  



Replication rights should \*\*never be granted casually\*\*.



---



\## Common Misconceptions



\*\*“They only have read access.”\*\*  

Replication is not read-only; it exposes credential secrets.



\*\*“They’re a service account, so it’s fine.”\*\*  

Service accounts are frequently targeted and abused.



\*\*“We would see this in logs.”\*\*  

DCSync activity often blends into normal replication traffic.



---



\## Risk Perspective



If an attacker has \*\*DCSync capability\*\*, everything else in the domain becomes irrelevant.



Protecting replication rights is one of the \*\*highest-impact security controls\*\* in Active Directory.



