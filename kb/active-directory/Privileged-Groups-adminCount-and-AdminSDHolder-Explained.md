Privileged Groups, adminCount, and AdminSDHolder Explained

Purpose



This knowledge base article explains how privileged access is enforced and maintained in Active Directory through privileged groups, the adminCount attribute, and the AdminSDHolder protection mechanism.



These components are foundational to Active Directory security and are also a frequent source of misunderstanding, stale privilege, and unintended risk.



Privileged Groups in Active Directory



Active Directory includes several built-in groups that grant Tier-0 or near Tier-0 authority. Membership in these groups provides elevated permissions that affect the entire domain or forest.



Common privileged groups include:



Domain Admins



Enterprise Admins



Schema Admins



Administrators



Account Operators



Backup Operators



Server Operators



DnsAdmins



Group Policy Creator Owners



Membership in any of these groups should be considered high-impact and tightly controlled.



How Privilege Is Enforced



Privilege in Active Directory is enforced through a combination of:



Group membership



Access control lists (ACLs)



Inherited permissions



Protection mechanisms designed to prevent accidental delegation



One of the most important—and least understood—of these mechanisms is AdminSDHolder.



What Is AdminSDHolder?



AdminSDHolder is a protected object located in:



CN=AdminSDHolder,CN=System,<domain DN>





It acts as a template security descriptor for privileged accounts and groups.



Objects considered “protected” by AdminSDHolder receive:



A standardized ACL



Removal of inherited permissions



Periodic re-application of this ACL by the SDProp process



This ensures privileged objects cannot be accidentally or maliciously delegated through inheritance.



The adminCount Attribute



The adminCount attribute is used to track whether an object is (or has been) protected by AdminSDHolder.



adminCount = 1

Indicates the object is treated as privileged and subject to AdminSDHolder protection.



Key behavior:



Once set, adminCount is not automatically cleared



Removing a user from a privileged group does not reset adminCount



AdminSDHolder protection may continue even after privilege is removed



This leads to a common problem: stale privileged objects.



Stale adminCount and Why It Matters



A user with:



adminCount = 1



No current membership in privileged groups



Is often a sign of:



Historical privilege



Incomplete deprovisioning



Legacy administrative practices



Risks associated with stale adminCount:



Blocked inheritance prevents delegated controls from applying



Overly permissive ACLs may remain in place



Security teams may assume the account is non-privileged when it is still protected



These accounts should be explicitly reviewed and remediated.



Protected Users Group



The Protected Users group provides additional authentication hardening for sensitive accounts.



When a user is a member:



NTLM authentication is blocked



Legacy Kerberos encryption types are disabled



Credential delegation is restricted



Protected Users is most appropriate for:



Tier-0 administrative accounts



Highly sensitive service or break-glass accounts



However, it can break legacy applications, so membership must be validated carefully.



adminCount vs. Protected Users



These two mechanisms are complementary but serve different purposes:



Feature	adminCount / AdminSDHolder	Protected Users

Focus	Authorization \& ACLs	Authentication hardening

Automatic	Yes (via SDProp)	No

Prevents delegation	Indirectly	Yes

Blocks NTLM	No	Yes

Breaks legacy auth	Rarely	Sometimes



An account may require:



AdminSDHolder protection



Protected Users membership



Or both



Common Misconceptions



“adminCount means the user is currently an admin.”

Not necessarily. It often means the user was an admin at some point.



“Removing from Domain Admins fixes everything.”

It does not clear adminCount or restore inheritance.



“Protected Users replaces good privilege hygiene.”

It does not. It is an additional control, not a substitute.



How This Is Assessed



This repository includes scripts that:



Identify users with adminCount = 1



Detect stale adminCount conditions



Inventory privileged group membership



Evaluate Protected Users coverage



Flag disabled or inactive privileged accounts



These checks provide evidence-based visibility, not automatic judgment.



Recommended Review Workflow



Identify all privileged group members



Review users with adminCount = 1



Validate whether privilege is still required



Clear stale adminCount where appropriate



Evaluate Protected Users eligibility



Document intent for all exceptions



Risk Perspective



Mismanaged privileged identity is one of the most common root causes of Active Directory compromise.



AdminSDHolder and adminCount exist to protect the domain—but without regular review, they can quietly preserve unnecessary privilege.

