\# Robocopy Usage Guide (Reliable File Copy for Windows)



Robocopy (Robust File Copy) is a Windows-native command-line tool designed for reliable, restartable, and high-performance file copy operations. It is commonly used for data migrations, backup staging, server moves, and large-scale file transfers where standard copy methods are insufficient.



This article explains \*\*when to use Robocopy\*\*, \*\*how it behaves\*\*, and \*\*how to use it safely and effectively\*\* in production environments.



---



\## Purpose



Use Robocopy to:



\* Copy large datasets reliably across local disks, servers, and network shares

\* Resume interrupted transfers without starting over

\* Preserve file metadata (timestamps, attributes, permissions)

\* Perform high-performance, multi-threaded copies

\* Generate detailed logs suitable for audits and troubleshooting



Robocopy is included with modern versions of Windows and does not require additional installation.



---



\## When to Use Robocopy



Robocopy is appropriate for:



\* Server migrations (file servers, application data, user shares)

\* Backup staging or pre-seeding data

\* Large one-time copy jobs

\* Re-syncing data sets where only changes should be copied

\* Copying data over unstable or slow network links



Robocopy is \*\*not\*\* intended to replace enterprise backup solutions. It does not provide versioning, retention, or point-in-time recovery on its own.



---



\## Core Concepts



\### Restartable Copies



Robocopy can resume a copy operation after interruption without restarting the entire job.



\### Incremental Behavior



By default, Robocopy only copies files that are new or have changed, making it efficient for repeated runs.



\### Exit Codes



Robocopy uses \*\*bitmask-based exit codes\*\*, not simple success/failure values. Exit codes from `0` to `7` typically indicate successful operations with varying conditions (e.g., files copied, extra files detected).



---



\## Commonly Used Flags



\* `/E`

&nbsp; Copies all subdirectories, including empty ones.



\* `/Z`

&nbsp; Enables restartable mode for network resilience.



\* `/R:n`

&nbsp; Number of retry attempts for failed copies.



\* `/W:n`

&nbsp; Wait time (in seconds) between retries.



\* `/MT:n`

&nbsp; Enables multi-threaded copying (default maximum is 128).



\* `/COPY:DAT`

&nbsp; Copies data, attributes, and timestamps.



\* `/DCOPY:T`

&nbsp; Preserves directory timestamps.



\* `/MIR`

&nbsp; Mirrors source to destination (includes deletions).

&nbsp; \*\*Use with extreme caution.\*\*



\* `/L`

&nbsp; List-only mode (dry run).



\* `/LOG:path`

&nbsp; Writes output to a log file.



---



\## Recommended Safe Defaults



The following defaults are commonly used for migrations and backup staging:



\* Restartable mode enabled

\* Limited retry count

\* Moderate multi-threading

\* No deletions unless explicitly required

\* Logging enabled



---



\## Example: Basic Copy



```powershell

robocopy "D:\\Data" "\\\\NAS01\\Backups\\Data" /E /Z /R:3 /W:5 /COPY:DAT /DCOPY:T

```



Copies all data from `D:\\Data` to the destination share, preserving metadata and retrying transient failures.



---



\## Example: Multi-Threaded Copy with Logging



```powershell

robocopy "D:\\Shares" "E:\\Shares" /E /Z /MT:16 /R:3 /W:5 /LOG:C:\\Logs\\robocopy.log

```



Uses 16 threads and writes a detailed log file for review.



---



\## Example: Dry Run (No Changes)



```powershell

robocopy "D:\\Data" "\\\\Server02\\Data" /E /L

```



Displays what \*would\* be copied without making any changes. This should be used before any destructive operation.



---



\## Example: Mirror (Destructive)



```powershell

robocopy "D:\\Source" "E:\\Destination" /MIR

```



Mirrors the source exactly, deleting files in the destination that do not exist in the source.



\*\*Always run with `/L` first before using `/MIR`.\*\*



---



\## Robocopy Exit Codes (Summary)



\* `0` – No files copied, no failures

\* `1` – Files copied successfully

\* `2` – Extra files detected (no copies)

\* `3` – Files copied and extra files detected

\* `5` – Files copied and mismatches detected

\* `7` – Files copied with mismatches and extra files

\* `8+` – Failure conditions (attention required)



Exit codes `0–7` are generally considered \*\*successful outcomes\*\*, depending on context.



---



\## PowerShell Wrapper Usage



For repeatable, documented execution, a PowerShell wrapper script is recommended. This allows:



\* Parameterized source and destination paths

\* Controlled use of destructive flags

\* Consistent logging

\* Structured output for SOPs and audits



Example usage with a wrapper script:



```powershell

.\\Invoke-Robocopy.ps1 -Source "D:\\Data" -Destination "\\\\NAS01\\Backups\\Data" -Threads 16 -LogPath "C:\\Logs\\robocopy.log"

```



---



\## Operational Notes



\* Always validate source and destination paths before execution

\* Use dry-run mode before any mirror operation

\* Avoid running Robocopy concurrently against the same destination

\* Monitor disk space on both source and destination

\* Preserve logs for change records and incident investigations



---



\## Summary



Robocopy is a powerful and reliable tool for large-scale file copy operations when used deliberately. With safe defaults, proper logging, and careful handling of destructive flags, it is well-suited for migrations, backup staging, and operational maintenance in enterprise and MSP environments.



