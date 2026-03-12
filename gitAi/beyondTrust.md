

Subject: BeyondTrust allowlist request — git-ai binary

Hi,

Can you add the following path to the BeyondTrust allowlist?

Path: C:\Users\*\.git-ai\bin\*

This is a Git extension (git-ai) that wraps git.exe. Defendpoint is scanning it on every call, adding ~3-5 seconds overhead per Git command. IDEs call Git constantly, so this makes development unusable.

Native git: 150ms per call
With BeyondTrust scanning git-ai: 3,000-5,000ms per call

Open source repo for review: https://github.com/git-ai-project/git-ai

Thanks,
Avri








Subject: Request: BeyondTrust allowlist for git-ai developer tool

Hi,

I'm requesting an allowlist entry in BeyondTrust Privilege Management for a developer tool called Git AI (git-ai), which is an open-source Git extension we use for tracking AI-generated code.

The tool installs a small binary that wraps Git commands. Currently, BeyondTrust's Defendpoint service scans this binary on every execution, adding ~3-5 seconds of overhead per Git call. Since VS Code and Cursor invoke Git dozens of times per minute, this causes severe IDE slowdowns and accumulation of suspended git.exe processes in Task Manager.

Benchmark data from my machine:
- Native git.exe: ~150ms
- git-ai with Defender exclusion only: ~3,000ms
- git-ai without any exclusions: ~4,800ms

Requested change:
Add the following path to BeyondTrust's application allowlist:
- C:\Users\*\.git-ai\bin\git.exe
- Or broader: C:\Users\*\.git-ai\bin\*

This should be applied as an org-wide policy for all developers using git-ai.

The tool is open source and can be reviewed here: https://github.com/git-ai-project/git-ai

Thanks,
Avri