# ```markdown

# \# technical-kb

# 

# A curated collection of technical knowledge base (KB) articles and standard operating procedures (SOPs) covering infrastructure, Windows, networking, cloud, backup, and automation topics.

# 

# This repository is designed to serve both as a working reference library and as an example of professional, production-grade technical documentation.

# 

# ---

# 

# \## Purpose

# 

# The purpose of this repository is to:

# 

# \- Capture reusable technical knowledge in a clear, structured format  

# \- Provide repeatable SOPs for common infrastructure and operations tasks  

# \- Demonstrate documentation standards suitable for enterprise, MSP, and regulated environments  

# \- Serve as a reference portfolio for technical writing, systems engineering, and operational maturity  

# 

# All content is written to be:

# \- Tool-agnostic where possible  

# \- Environment-safe (no credentials, secrets, or client-identifying data)  

# \- Readable by engineers, auditors, and technical stakeholders  

# 

# ---

# 

# \## Intended Audience

# 

# \- Systems Engineers  

# \- Infrastructure \& Cloud Engineers  

# \- MSP Technical Staff  

# \- Technical Leads and Architects  

# \- Auditors and Compliance Reviewers  

# \- Engineers building or maintaining internal KBs  

# 

# ---

# 

# \## Repository Structure

# 

# \### `kb/`

# Technical knowledge base articles organized by domain.

# 

# \- `kb/active-directory/`  

# &nbsp; Active Directory–focused knowledge base content.

# 

# &nbsp; - `ad-health-check-guide.md`  

# &nbsp;   Primary KB article describing Domain Controller and AD health validation.

# 

# &nbsp; - `scripts/`  

# &nbsp;   Supporting PowerShell diagnostic scripts referenced by AD KB articles.

# 

# &nbsp;   - `Invoke-DCHealthCheck.ps1`  

# &nbsp;     Orchestrates the full DC health check sequence.

# 

# &nbsp;   - `Test-DCPrereqs.ps1`  

# &nbsp;     Validates baseline requirements before deeper diagnostics.

# 

# &nbsp;   - `Get-ADCriticalEvents.ps1`  

# &nbsp;     Collects high-signal AD-related warning and error events.

# 

# &nbsp;   - `Test-DCDiag.ps1`  

# &nbsp;     Executes and evaluates DCDIAG results.

# 

# &nbsp;   - `Test-ADReplication.ps1`  

# &nbsp;     Assesses Active Directory replication health.

# 

# &nbsp;   - `Test-DNSHealth.ps1`  

# &nbsp;     Validates DNS configuration and AD-critical DNS records.

# 

# &nbsp;   - `Test-SYSVOLDFSR.ps1`  

# &nbsp;     Checks SYSVOL availability and DFS Replication health.

# 

# &nbsp;   - `Test-TimeSync.ps1`  

# &nbsp;     Evaluates Windows Time configuration and synchronization.

# 

# &nbsp;   - `Test-DCServices.ps1`  

# &nbsp;     Verifies core Domain Controller services.

# 

# &nbsp;   - `Test-NTDSDatabase.ps1`  

# &nbsp;     Reviews NTDS database configuration, disk health, and ESENT signals.

# 

# &nbsp;   - `\_shared/`  

# &nbsp;     Shared helper utilities used by multiple scripts.

# &nbsp;     - `Assert-RunAsAdmin.ps1`

# &nbsp;     - `Write-HealthLog.ps1`

# 

# ---

# 

# \### `sop/`

# Standard Operating Procedures written as repeatable operational runbooks, such as:

# \- Pre-migration and post-migration validation

# \- User onboarding and offboarding

# \- Backup and recovery workflows

# \- Infrastructure change validation

# 

# ---

# 

# \## Usage Notes

# 

# \- KB articles describe concepts, diagnostics, and decision-making.

# \- Scripts provide supporting evidence and diagnostics referenced by KB articles.

# \- SOPs define step-by-step operational procedures.

# \- All scripts are read-only and safe to execute in production environments when run with appropriate privileges.

# 

# ---

# 

# \## Documentation Standards

# 

# \- Markdown-first format

# \- Clear scope and purpose per document

# \- Explicit “when to use” guidance

# \- No embedded secrets or environment-specific identifiers

# \- Suitable for internal KBs, audits, and professional review

# ```



# 

