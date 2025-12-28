\## Networking Health Check Scripts



This section contains a comprehensive collection of \*\*read-only PowerShell scripts\*\* designed to diagnose, baseline, and troubleshoot Windows networking issues. These scripts are suitable for use during outages, pre-migration assessments, post-change validation, and ongoing health checks across servers, workstations, and domain controllers.



The scripts are modular and can be run individually or orchestrated together for a full network health assessment.

\## Networking Health Check Scripts



This section contains a comprehensive collection of \*\*read-only PowerShell scripts\*\* designed to diagnose, baseline, and troubleshoot Windows networking issues. These scripts are suitable for use during outages, pre-migration assessments, post-change validation, and ongoing health checks across servers, workstations, and domain controllers.



The scripts are modular and can be run individually or orchestrated together for a full network health assessment.



---



\## Purpose



The networking scripts are intended to help answer the following questions quickly and defensibly:



\* Is this a network-layer problem?

\* If so, where is the failure (IP, DNS, routing, firewall, VPN, IPSec, or transport)?

\* Is the issue transient, configuration-based, or systemic?

\* Can this be proven with collected evidence?



All scripts are:



\* Non-destructive

\* Safe for production environments

\* Designed for MSP, enterprise, and regulated environments

\* Suitable for attachment to tickets, incident reports, and audits



---



\## Folder Structure



\* `\_shared`

&nbsp; Common helper functions used across networking scripts (logging, admin checks, module validation)



\* Root `scripts` folder

&nbsp; Individual diagnostic and reporting scripts



---



\## Script Overview and When to Use Them



\### Orchestration and Reporting



\*\*Invoke-NetworkHealthCheck.ps1\*\*

Runs a standardized sequence of networking checks and writes structured output to a run folder.

Use this during incidents, pre-migration validation, or when collecting full evidence for escalation.



\*\*Export-NetworkHealthReport.ps1\*\*

Consolidates results from a network health run into a single JSON report, with optional CSV and text summaries.

Use this for documentation, ticket attachments, or audit artifacts.



---



\### IP, Routing, and Core Connectivity



\*\*Test-IPAddressing.ps1\*\*

Validates local IP configuration and flags high-risk conditions such as APIPA addresses, missing gateways, duplicate IPs, and missing DNS servers.

Use this first when connectivity is broken or intermittent.



\*\*Test-GatewayReachability.ps1\*\*

Confirms reachability of default gateways.

Use when clients or servers can reach local resources but not upstream networks.



\*\*Test-RoutingTable.ps1\*\*

Analyzes the routing table, default routes, and route metrics.

Use when VPNs, multiple NICs, or asymmetric routing is suspected.



---



\### DNS and Name Resolution



\*\*Test-DNSResolution.ps1\*\*

Tests forward and reverse DNS resolution against configured DNS servers.

Use when applications fail by name but work by IP, or during domain-related issues.



\*\*Test-NameResolutionOrder.ps1\*\*

Evaluates DNS suffix search order, per-adapter DNS registration, NRPT rules, and hosts file metadata.

Use when name resolution behaves inconsistently across networks or VPNs.



---



\### Performance and Reliability



\*\*Test-NetworkLatency.ps1\*\*

Measures ICMP latency and jitter to one or more targets.

Use to identify slow or unstable network paths.



\*\*Test-PacketLoss.ps1\*\*

Detects intermittent packet loss and consecutive failure streaks.

Use for diagnosing WAN, Wi-Fi, or VPN instability.



\*\*Test-MTU.ps1\*\*

Performs MTU discovery using “Don’t Fragment” probes.

Use when VPNs, IPSec tunnels, or Azure connectivity fail intermittently or only for certain applications.



---



\### Adapter, Stack, and Firewall State



\*\*Get-NetworkConfiguration.ps1\*\*

Captures a full snapshot of adapters, IP configuration, DNS, proxy settings, and hosts file metadata.

Use for baselining and documentation.



\*\*Get-NetworkAdapterStatus.ps1\*\*

Reports adapter state, link speed, driver info, and offload settings (best-effort).

Use when link flapping, performance degradation, or driver issues are suspected.



\*\*Get-NetworkBindings.ps1\*\*

Inspects protocol and client bindings (IPv4, IPv6, Client for Microsoft Networks, File and Printer Sharing).

Use when modern Windows networking behaves unpredictably or legacy “IPv6 disabled” configurations exist.



\*\*Get-FirewallProfileStatus.ps1\*\*

Reports Windows Firewall profile state and flags risky configurations.

Use when traffic is unexpectedly blocked or security posture is under review.



---



\### Ports, VPN, and IPSec



\*\*Test-PortConnectivity.ps1\*\*

Tests TCP and best-effort UDP connectivity to specific targets and ports.

Use to validate application dependencies, DC ports, or firewall rules.



\*\*Test-VPNConnectivity.ps1\*\*

Inspects VPN adapters, DNS configuration, routes, and RAS connection state.

Use when VPN users report partial connectivity or split-tunnel issues.



\*\*Test-IPSecHealth.ps1\*\*

Checks IPSec/IKE services, security associations, and related event logs.

Use for site-to-site VPNs, Always On VPN, Azure VPN, and firewall tunnel troubleshooting.



---



\### Telemetry and Evidence



\*\*Get-NetworkCriticalEvents.ps1\*\*

Collects high-signal networking-related events from Windows event logs.

Use for incident timelines and root-cause analysis.



\*\*Get-TcpipStatistics.ps1\*\*

Captures TCP/IP stack statistics and adapter error counters.

Use to differentiate application failures from transport-layer problems.



---



\## Typical Usage Patterns



Run a full network health check:



```powershell

.\\Invoke-NetworkHealthCheck.ps1

```



Test IP configuration and routing during an outage:



```powershell

.\\Test-IPAddressing.ps1

.\\Test-RoutingTable.ps1

```



Validate DNS behavior:



```powershell

.\\Test-DNSResolution.ps1

.\\Test-NameResolutionOrder.ps1

```



Export a consolidated report:



```powershell

.\\Export-NetworkHealthReport.ps1 -RunPath C:\\Reports\\NetworkHealth\\Run\_2025-01-15 -ExportCsv -ExportText

```



---



\## Design Notes



\* No scripts modify system configuration

\* No credentials or secrets are read or stored

\* Output is structured for automation, reporting, and auditing

\* Scripts are designed to complement Active Directory, Windows, and Cloud health checks in this repository



This section is intended to function as a \*\*network troubleshooting playbook\*\*, not just a script dump.



---



\## Purpose



The networking scripts are intended to help answer the following questions quickly and defensibly:



\* Is this a network-layer problem?

\* If so, where is the failure (IP, DNS, routing, firewall, VPN, IPSec, or transport)?

\* Is the issue transient, configuration-based, or systemic?

\* Can this be proven with collected evidence?



All scripts are:



\* Non-destructive

\* Safe for production environments

\* Designed for MSP, enterprise, and regulated environments

\* Suitable for attachment to tickets, incident reports, and audits



---



\## Folder Structure



\* `\_shared`

&nbsp; Common helper functions used across networking scripts (logging, admin checks, module validation)



\* Root `scripts` folder

&nbsp; Individual diagnostic and reporting scripts



---



\## Script Overview and When to Use Them



\### Orchestration and Reporting



\*\*Invoke-NetworkHealthCheck.ps1\*\*

Runs a standardized sequence of networking checks and writes structured output to a run folder.

Use this during incidents, pre-migration validation, or when collecting full evidence for escalation.



\*\*Export-NetworkHealthReport.ps1\*\*

Consolidates results from a network health run into a single JSON report, with optional CSV and text summaries.

Use this for documentation, ticket attachments, or audit artifacts.



---



\### IP, Routing, and Core Connectivity



\*\*Test-IPAddressing.ps1\*\*

Validates local IP configuration and flags high-risk conditions such as APIPA addresses, missing gateways, duplicate IPs, and missing DNS servers.

Use this first when connectivity is broken or intermittent.



\*\*Test-GatewayReachability.ps1\*\*

Confirms reachability of default gateways.

Use when clients or servers can reach local resources but not upstream networks.



\*\*Test-RoutingTable.ps1\*\*

Analyzes the routing table, default routes, and route metrics.

Use when VPNs, multiple NICs, or asymmetric routing is suspected.



---



\### DNS and Name Resolution



\*\*Test-DNSResolution.ps1\*\*

Tests forward and reverse DNS resolution against configured DNS servers.

Use when applications fail by name but work by IP, or during domain-related issues.



\*\*Test-NameResolutionOrder.ps1\*\*

Evaluates DNS suffix search order, per-adapter DNS registration, NRPT rules, and hosts file metadata.

Use when name resolution behaves inconsistently across networks or VPNs.



---



\### Performance and Reliability



\*\*Test-NetworkLatency.ps1\*\*

Measures ICMP latency and jitter to one or more targets.

Use to identify slow or unstable network paths.



\*\*Test-PacketLoss.ps1\*\*

Detects intermittent packet loss and consecutive failure streaks.

Use for diagnosing WAN, Wi-Fi, or VPN instability.



\*\*Test-MTU.ps1\*\*

Performs MTU discovery using “Don’t Fragment” probes.

Use when VPNs, IPSec tunnels, or Azure connectivity fail intermittently or only for certain applications.



---



\### Adapter, Stack, and Firewall State



\*\*Get-NetworkConfiguration.ps1\*\*

Captures a full snapshot of adapters, IP configuration, DNS, proxy settings, and hosts file metadata.

Use for baselining and documentation.



\*\*Get-NetworkAdapterStatus.ps1\*\*

Reports adapter state, link speed, driver info, and offload settings (best-effort).

Use when link flapping, performance degradation, or driver issues are suspected.



\*\*Get-NetworkBindings.ps1\*\*

Inspects protocol and client bindings (IPv4, IPv6, Client for Microsoft Networks, File and Printer Sharing).

Use when modern Windows networking behaves unpredictably or legacy “IPv6 disabled” configurations exist.



\*\*Get-FirewallProfileStatus.ps1\*\*

Reports Windows Firewall profile state and flags risky configurations.

Use when traffic is unexpectedly blocked or security posture is under review.



---



\### Ports, VPN, and IPSec



\*\*Test-PortConnectivity.ps1\*\*

Tests TCP and best-effort UDP connectivity to specific targets and ports.

Use to validate application dependencies, DC ports, or firewall rules.



\*\*Test-VPNConnectivity.ps1\*\*

Inspects VPN adapters, DNS configuration, routes, and RAS connection state.

Use when VPN users report partial connectivity or split-tunnel issues.



\*\*Test-IPSecHealth.ps1\*\*

Checks IPSec/IKE services, security associations, and related event logs.

Use for site-to-site VPNs, Always On VPN, Azure VPN, and firewall tunnel troubleshooting.



---



\### Telemetry and Evidence



\*\*Get-NetworkCriticalEvents.ps1\*\*

Collects high-signal networking-related events from Windows event logs.

Use for incident timelines and root-cause analysis.



\*\*Get-TcpipStatistics.ps1\*\*

Captures TCP/IP stack statistics and adapter error counters.

Use to differentiate application failures from transport-layer problems.



---



\## Typical Usage Patterns



Run a full network health check:



```powershell

.\\Invoke-NetworkHealthCheck.ps1

```



Test IP configuration and routing during an outage:



```powershell

.\\Test-IPAddressing.ps1

.\\Test-RoutingTable.ps1

```



Validate DNS behavior:



```powershell

.\\Test-DNSResolution.ps1

.\\Test-NameResolutionOrder.ps1

```



Export a consolidated report:



```powershell

.\\Export-NetworkHealthReport.ps1 -RunPath C:\\Reports\\NetworkHealth\\Run\_2025-01-15 -ExportCsv -ExportText

```



---



\## Design Notes



\* No scripts modify system configuration

\* No credentials or secrets are read or stored

\* Output is structured for automation, reporting, and auditing

\* Scripts are designed to complement Active Directory, Windows, and Cloud health checks in this repository



This section is intended to function as a \*\*network troubleshooting playbook\*\*, not just a script dump.



