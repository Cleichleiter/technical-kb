Kerberos Encryption Types and Legacy Crypto Risks

Purpose



This knowledge base article explains Kerberos encryption types used in Active Directory and why legacy cryptographic settings significantly weaken authentication security, even in otherwise well-managed environments.



Kerberos crypto issues are often subtle, rarely visible in daily operations, and frequently persist long after systems are modernized.



Kerberos Encryption in Active Directory



Kerberos uses symmetric encryption to protect:



Authentication tickets (TGTs)



Service tickets



Credential exchanges between clients and services



Active Directory supports multiple encryption types to maintain backward compatibility with older systems and applications.



Over time, this compatibility becomes a security liability.



Common Kerberos Encryption Types

DES (Data Encryption Standard)



DES-CBC-CRC



DES-CBC-MD5



Status: Deprecated

Risk Level: High



DES is cryptographically broken and should not be used in any modern environment.



RC4-HMAC



Status: Legacy

Risk Level: Medium to High



RC4 remains widely enabled due to historical compatibility but is vulnerable to:



Offline cracking



Kerberoasting amplification



Downgrade attacks



RC4 is especially dangerous for service accounts.



AES128 and AES256



Status: Modern

Risk Level: Low



AES encryption provides significantly stronger protection and should be preferred for:



Service accounts



Computer accounts



Privileged users



AES support depends on:



Domain controller OS level



Account configuration



Functional level readiness



How Encryption Types Are Configured



Kerberos encryption behavior is influenced by:



Domain controller OS capabilities



Domain and forest functional levels



Account-level settings (msDS-SupportedEncryptionTypes)



Group Policy and registry settings



Application compatibility requirements



When encryption types are not explicitly configured, legacy defaults may apply.



Service Accounts and SPNs



Service accounts are especially sensitive because:



They often have SPNs



They are frequently long-lived



They are prime targets for Kerberoasting



Risk patterns include:



RC4-only service accounts



DES-enabled service accounts



Privileged service accounts without AES enabled



These configurations dramatically lower the cost of offline attacks.



Domain Controllers and Crypto Baseline



Kerberos encryption strength is constrained by:



The oldest domain controller OS in the domain



Forest functional level



Patch level consistency



Legacy domain controllers can:



Prevent AES-only enforcement



Force weaker encryption for compatibility



Delay security hardening initiatives



How Crypto Posture Is Assessed



The scripts in this repository evaluate:



Domain and forest functional levels



Domain controller operating systems



Service accounts with SPNs



Computer accounts and their encryption flags



Presence of DES-enabled or RC4-only configurations



The assessment provides signals, not enforcement.



Interpreting Findings



Crypto findings are typically rated:



High



DES-enabled accounts



DES-enabled service principals



Medium



RC4-only service or computer accounts



Low



Functional level limitations affecting crypto hardening



Info



Inventory of encryption posture



Not all legacy crypto can be removed immediately, but it should always be explicitly acknowledged.



Remediation Guidance



When legacy crypto is identified:



Identify applications using affected accounts



Test AES enablement in non-production



Enable AES128/AES256 on service accounts



Remove DES support wherever possible



Plan domain controller OS upgrades



Document unavoidable legacy dependencies



Crypto hardening should be incremental and validated.



Common Misconceptions



“We’re using Kerberos, so it’s secure.”

Kerberos is only as strong as its encryption configuration.



“RC4 is still supported, so it’s fine.”

Supported does not mean secure.



“This would break everything.”

Often it does not—but testing is required.



Risk Perspective



Legacy cryptography weakens authentication silently.



Over time, it converts strong identity controls into cheap offline attack opportunities.

