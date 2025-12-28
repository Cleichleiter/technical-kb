\# Kerberos Delegation Risks: Unconstrained, Constrained, and RBCD



\## Purpose



This knowledge base article explains \*\*Kerberos delegation\*\* in Active Directory and why misconfigured delegation is one of the most common ways attackers \*\*expand blast radius after initial access\*\*.



Delegation is often required for legitimate application functionality, but when poorly understood or broadly applied, it creates \*\*high-impact privilege escalation paths\*\*.



---



\## What Is Kerberos Delegation?



Kerberos delegation allows a service to:



\- Accept a user’s authentication

\- Act on that user’s behalf

\- Access other services using the user’s identity



This is commonly used by:



\- Web applications

\- File services

\- Application tiers that require backend access



Delegation is not inherently insecure, but it must be \*\*tightly scoped and intentionally designed\*\*.



---



\## Why Delegation Is Dangerous



Delegation is dangerous because it:



\- Moves credentials beyond the original authentication boundary

\- Allows impersonation of privileged users

\- Can expose Kerberos tickets to attackers

\- Often persists unnoticed for years



When abused, delegation allows attackers to:



\- Impersonate Domain Admins

\- Access critical services

\- Move laterally without passwords



---



\## Types of Kerberos Delegation



\### Unconstrained Delegation



| Attribute | Value |

|--------|------|

| Scope | Any service in the domain |

| Risk Level | High |



\*\*Key characteristics:\*\*

\- Full delegation scope

\- TGTs are stored on the delegating system

\- Any compromised service can impersonate any user



\*\*Common abuse scenario:\*\*  

If a Domain Admin authenticates to a system with unconstrained delegation, their TGT can be reused by an attacker.



---



\### Constrained Delegation



| Attribute | Value |

|--------|------|

| Scope | Specific target services |

| Risk Level | Medium (context-dependent) |



\*\*Key characteristics:\*\*

\- Reduced scope compared to unconstrained delegation

\- Still allows impersonation

\- Misconfiguration can quietly expand access



\*\*Key risk:\*\*  

Delegation to high-value services (LDAP, CIFS, HOST) can still enable domain compromise.



---



\### Resource-Based Constrained Delegation (RBCD)



| Attribute | Value |

|--------|------|

| Scope | Controlled by target service |

| Risk Level | Medium to High |



\*\*Key characteristics:\*\*

\- Delegation defined on the target object

\- Common in modern environments

\- Frequently abused through ACL misconfiguration



Risk depends heavily on \*\*who can modify the target object\*\*.



---



\## Delegation and Privileged Accounts



Delegation becomes significantly more dangerous when it involves:



\- Privileged users

\- Service accounts with elevated rights

\- Accounts not marked as non-delegatable



\### “Account Is Sensitive and Cannot Be Delegated”



This account flag:



\- Prevents Kerberos delegation of the account

\- Should be set on privileged and Tier-0 users

\- Reduces blast radius even when delegation exists



Failure to use this control greatly increases risk.



---



\## Common Delegation Misconfigurations



\- Unconstrained delegation on general-purpose servers

\- Delegation on systems accessed by administrators

\- Delegation combined with SPN-bearing service accounts

\- RBCD where too many principals can modify the target

\- Lack of documentation explaining why delegation exists



---



\## How Delegation Is Assessed



The scripts in this repository:



\- Identify unconstrained delegation on users and computers

\- Inventory constrained delegation targets

\- Detect RBCD configurations

\- Flag privileged accounts that are delegatable

\- Highlight privileged accounts with SPNs and delegation exposure



All checks are \*\*read-only\*\* and designed to surface \*\*reviewable evidence\*\*.



---



\## Interpreting Findings



Delegation findings are typically rated as follows:



\### High

\- Unconstrained delegation

\- Privileged accounts that are delegatable

\- Delegation involving Tier-0 services



\### Medium

\- Constrained delegation requiring validation

\- RBCD with unclear modification boundaries



\### Info

\- Delegation inventory and visibility



Delegation findings should always be \*\*reviewed in context\*\*, not blindly removed.



---



\## Remediation Guidance



When delegation risks are identified:



1\. Validate the business requirement

2\. Prefer constrained delegation or RBCD over unconstrained

3\. Restrict delegation targets aggressively

4\. Set “Account is sensitive and cannot be delegated” on privileged users

5\. Limit who can modify RBCD attributes

6\. Document all approved delegation paths



Never remove delegation without confirming application impact.



---



\## Common Misconceptions



\*\*“Delegation is required, so it’s fine.”\*\*  

Delegation must still be scoped and hardened.



\*\*“RBCD is always safe.”\*\*  

RBCD is only as secure as the ACLs protecting it.



\*\*“Admins never log into those systems.”\*\*  

In practice, they eventually do.



---



\## Risk Perspective



Delegation expands trust boundaries inside Active Directory.



Poorly controlled delegation often turns \*\*one compromised system into many\*\*.



