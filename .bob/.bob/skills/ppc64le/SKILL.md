---
name: ppc64le-github-actions
description: Use this skill when analyzing a GitHub Actions workflow (.github/workflows/*.yml or *.yaml) to add ppc64le architecture support so CI can run on an ubuntu-24.04-ppc64le runner. Trigger when the user asks to port/add/enable ppc64le (or "power" architecture) support to a workflow, wants a matrix-vs-separate-job recommendation for a new architecture, or asks for a ppc64le CI enablement guide. Produces a Markdown implementation guide, not a modified workflow file. Do not use for general application-code porting, Dockerfile-only changes unrelated to a workflow, or non-GitHub-Actions CI systems.
---

# GitHub Actions ppc64le Workflow Support Skill

## Purpose

This skill analyzes an open-source project's **GitHub Actions workflow files** and generates a Markdown implementation guide explaining how to add **ppc64le architecture support** so the workflow can run successfully on an `ubuntu-24.04-ppc64le` runner.

The skill is specifically concerned with **GitHub Actions workflows and CI configuration**.

It must not propose unrelated application-code changes unless they are directly required by the workflow to successfully install dependencies, build, test, or execute on ppc64le.

---

## Primary Objective

Given one or more GitHub Actions workflow files, determine:

1. Where ppc64le support should be added.
2. Whether ppc64le should be:
   * added to an existing matrix, or
   * implemented as a separate GitHub Actions job.
3. What runner configuration is required.
4. Whether existing architecture-specific conditions need modification.
5. Whether package installation/setup steps require ppc64le-specific handling.
6. Whether dependency installation commands need to change.
7. Whether build/test commands require architecture-specific changes.
8. Whether environment variables, setup actions, or shell commands need modification.
9. Whether existing workflow logic accidentally excludes ppc64le.
10. The exact workflow files and sections that should be modified.

The final output must be a **`.md` guide**, not a modified workflow file.

---

# Scope

## In Scope

Analyze and provide guidance for:

* `.github/workflows/*.yml`
* `.github/workflows/*.yaml`
* GitHub Actions jobs
* GitHub Actions matrices
* `runs-on`
* `strategy.matrix`
* `include`
* `exclude`
* architecture-specific conditions
* `if:` expressions
* GitHub Actions expressions
* OS/architecture detection
* package installation steps
* dependency installation steps
* setup actions
* compiler/toolchain setup
* Python/Node/Java/Go/Rust/etc. environment setup when performed by workflows
* `pip`, `npm`, `yarn`, `pnpm`, `cargo`, `go`, Maven, Gradle, apt, etc. commands when executed from workflows
* architecture-specific package indexes
* architecture-specific wheel/package repositories
* source builds triggered by workflow steps
* workflow environment variables
* shell commands
* build commands
* test commands
* caching configuration when architecture can affect correctness
* artifact naming when architecture can cause collisions
* workflow dependencies such as `needs:`
* reusable workflows
* workflow inputs and outputs
* GitHub Actions runner labels
* architecture detection using commands such as `uname -m`
* conditions involving `x86_64`, `amd64`, `arm64`, `aarch64`, or `ppc64le`

## Out of Scope

Do not perform or recommend unrelated changes to:

* application source code
* business logic
* API implementation
* unit tests themselves
* documentation unrelated to CI
* deployment infrastructure outside GitHub Actions
* Kubernetes manifests
* Dockerfiles unless they are directly invoked or configured by the workflow
* Terraform
* production infrastructure
* release processes unrelated to the workflow

If a workflow calls another file such as a Dockerfile, script, Makefile, or configuration file and that external file appears to require a change for ppc64le, mention it as a **dependency/blocker** in the generated guide rather than expanding the skill into a general source-code modification skill.

---

# Target Environment

The target architecture is:

```text
Architecture: ppc64le
Operating System: Ubuntu 24.04
Runner: ubuntu-24.04-ppc64le
```

The generated guide should assume that the desired result is:

> The GitHub Actions workflow can execute the relevant CI job successfully on an Ubuntu 24.04 ppc64le runner.

Do not assume that every project requires the same implementation.

---

# Analysis Strategy

The skill must inspect the workflow systematically.

## Step 1 — Identify Workflow Structure

Determine:

* workflow name
* triggering events
* jobs
* job dependencies
* reusable workflows
* matrices
* runner definitions
* setup steps
* build steps
* test steps
* installation steps
* caching
* artifact handling

Create a concise workflow map.

Example:

```text
Workflow
├── lint
├── unit-tests
│    └── matrix: Python × OS
├── build
└── integration-tests
```

---

# Step 2 — Identify Existing Architecture Handling

Search the workflow for architecture-related logic.

Look for:

```yaml
runs-on:
strategy:
matrix:
include:
exclude:
if:
```

Also search shell commands and expressions for:

```text
uname
uname -m
architecture
arch
x86_64
amd64
arm64
aarch64
ppc64le
powerpc64le
linux/amd64
```

Identify whether the workflow already supports architectures such as:

* amd64
* x86_64
* arm64
* aarch64

If another architecture is already supported, use its implementation pattern as a reference where appropriate.

---

# Step 3 — Determine Matrix vs Separate Job

The skill must explicitly decide whether ppc64le should be added to an existing matrix or implemented as a separate job.

## Prefer Matrix Addition When

Recommend adding ppc64le to the existing matrix when:

* the job performs the same logical CI workflow for every architecture
* setup steps are substantially identical
* build/test commands are architecture-independent
* only `runs-on` or a small number of variables differ
* the matrix already models OS/architecture combinations
* the workflow naturally supports architecture as a matrix dimension

Example:

```yaml
strategy:
  matrix:
    architecture:
      - amd64
      - arm64
      - ppc64le
```

Or:

```yaml
strategy:
  matrix:
    include:
      - os: ubuntu-24.04
        arch: amd64
        runner: ubuntu-24.04
      - os: ubuntu-24.04
        arch: ppc64le
        runner: ubuntu-24.04-ppc64le
```

## Prefer Separate Job When

Recommend a separate job when:

* ppc64le requires substantially different setup
* installation commands differ significantly
* existing matrix semantics cannot represent the runner cleanly
* the workflow uses hard-coded x86 assumptions
* ppc64le requires special package indexes
* ppc64le requires a different compiler/toolchain setup
* ppc64le requires different build/test commands
* the existing matrix would become unnecessarily complicated
* ppc64le requires additional environment preparation
* the existing job has architecture-specific logic that would become difficult to maintain

Example:

```yaml
jobs:
  test:
    ...

  test-ppc64le:
    runs-on: ubuntu-24.04-ppc64le
    ...
```

The generated guide must explain **why** one approach is preferred.

Do not simply say "add a ppc64le job."

---

# Step 4 — Analyze Runner Configuration

Inspect every `runs-on` definition.

Determine whether the workflow uses:

```yaml
runs-on: ubuntu-latest
```

or:

```yaml
runs-on: ubuntu-24.04
```

or a matrix-driven runner.

Determine the correct location where:

```yaml
ubuntu-24.04-ppc64le
```

should be introduced.

Check whether `runs-on` is:

* hard-coded
* matrix-driven
* dynamically generated
* controlled through `include`
* controlled through workflow inputs

The generated guide should provide the exact conceptual change.

---

# Step 5 — Analyze Matrix Configuration

If a matrix exists, inspect:

```yaml
matrix:
include:
exclude:
```

Determine:

* whether architecture already exists as a matrix dimension
* whether OS and architecture are coupled
* whether runner labels are generated from matrix values
* whether `include` is more appropriate than adding a new dimension
* whether `exclude` accidentally removes the ppc64le combination

For example, if the workflow has:

```yaml
matrix:
  os:
    - ubuntu-24.04
  python:
    - "3.11"
    - "3.12"
```

do not blindly recommend:

```yaml
arch:
  - amd64
  - ppc64le
```

because this may multiply the entire test matrix.

Instead, evaluate whether a targeted `include` entry is more appropriate:

```yaml
include:
  - os: ubuntu-24.04-ppc64le
    python: "3.11"
```

The generated guide must explain matrix expansion implications.

---

# Step 6 — Detect Architecture-Specific Conditions

Search for conditions such as:

```yaml
if: runner.arch == 'X64'
```

or shell logic such as:

```bash
if [[ "$(uname -m)" == "x86_64" ]]; then
```

or:

```bash
case "$(uname -m)" in
    x86_64)
        ...
        ;;
esac
```

Identify logic that would:

* skip ppc64le
* install incorrect packages
* download x86 binaries
* select an incompatible compiler
* use architecture-specific URLs
* assume `/usr/bin/x86_64-*`
* assume `amd64`
* assume `x86_64`

The guide must explain how these conditions should be extended.

Example:

```bash
case "$(uname -m)" in
    x86_64)
        ...
        ;;
    ppc64le)
        ...
        ;;
esac
```

---

# Step 7 — Analyze Installation and Setup Steps

This is a critical part of the analysis.

Inspect workflow commands such as:

```yaml
- uses: actions/setup-python
- uses: actions/setup-node
- uses: actions/setup-java
- uses: actions/setup-go
- run: pip install ...
- run: npm install
- run: apt-get install ...
- run: wget ...
- run: curl ...
- run: make ...
```

Determine whether they implicitly assume x86/amd64.

Look for:

* architecture-specific URLs
* prebuilt binaries
* package names
* manually downloaded executables
* compiler binaries
* package repositories
* wheel repositories
* npm native modules
* Rust binaries
* Go binaries
* Java native dependencies
* Python wheels
* system libraries

If ppc64le requires a different installation path, document it.

---

# Step 8 — Analyze Python Package Installation

If the workflow installs Python packages, inspect commands such as:

```bash
pip install
python -m pip install
pip install -r requirements.txt
pip install .
```

Determine whether the workflow assumes that binary wheels exist for the target architecture.

Pay particular attention to packages containing native extensions.

Potential concerns include:

* package has no ppc64le wheel
* package must be built from source
* package needs system dependencies
* package requires a ppc64le-specific wheel repository
* package version does not support ppc64le
* dependency resolution selects incompatible binaries

If an architecture-specific package index is already used elsewhere in the project, identify it.

Do not invent package repositories or URLs.

If the workflow requires information that cannot be determined from the repository, mark it as:

```text
Requires validation
```

rather than making unsupported assumptions.

---

# Step 9 — Analyze Binary Downloads

Search for:

```bash
wget
curl
aria2
gh release download
```

and URLs containing architecture identifiers.

Examples of suspicious patterns:

```text
amd64
x86_64
linux-amd64
linux-x86_64
x86
```

Determine whether downloaded binaries need a ppc64le equivalent.

The generated guide should clearly identify:

```text
Current behavior
→ Why it is incompatible
→ Required ppc64le behavior
```

---

# Step 10 — Analyze Build and Test Commands

Inspect:

```bash
make
cmake
pytest
npm test
go test
cargo test
mvn test
gradle test
```

Determine whether commands themselves are architecture-neutral.

If they are architecture-neutral, state that no workflow-level change is required.

If they depend on architecture-specific environment variables or binaries, document the required modification.

Do not recommend changing tests merely because they run on a different architecture.

---

# Step 11 — Analyze Caching

Inspect:

```yaml
actions/cache
actions/setup-*
```

and cache keys.

Look for keys that do not distinguish architecture.

For example:

```yaml
key: dependencies-${{ runner.os }}
```

may cause artifacts generated on one architecture to be reused on another.

Consider whether the cache key should include architecture:

```yaml
key: dependencies-${{ runner.os }}-${{ runner.arch }}
```

However, do not recommend this automatically.

Only recommend architecture-aware cache keys when the cached content can differ by architecture.

The generated guide must explain the reasoning.

---

# Step 12 — Analyze Artifacts

Inspect:

```yaml
actions/upload-artifact
actions/download-artifact
```

Determine whether multiple architectures can generate artifacts with identical names.

For example:

```yaml
name: build-artifact
```

may cause ambiguity when amd64 and ppc64le jobs run concurrently.

If necessary, recommend architecture-aware names:

```yaml
name: build-artifact-${{ runner.arch }}
```

Only recommend this when artifact collisions or ambiguity are realistically possible.

---

# Step 13 — Analyze Hard-Coded Architecture Assumptions

Search for common assumptions:

```text
amd64
x86_64
x86
linux-amd64
linux-x86_64
/opt/x86
/usr/local/x86
```

Also inspect:

```bash
dpkg --print-architecture
uname -m
arch
lscpu
```

Determine whether architecture detection is:

* correct
* incomplete
* unnecessary
* incompatible with ppc64le

For Ubuntu ppc64le, account for the architecture reported by the environment rather than assuming x86 naming conventions.

---

# Step 14 — Identify Third-Party GitHub Actions

Inspect all:

```yaml
uses:
```

entries.

Determine whether any third-party action may have architecture limitations.

Examples:

```yaml
uses: vendor/action@version
```

Do not claim that an action supports or does not support ppc64le unless this can be established from repository evidence.

Instead report:

```text
Potential compatibility concern:
The workflow uses <action>. Verify that the action supports execution on ppc64le runners.
```

If the action is implemented as a JavaScript action, Docker action, or composite action, distinguish these cases when possible.

---

# Step 15 — Produce a Change Classification

Every finding should be classified as one of:

### Required
The workflow cannot reasonably run on ppc64le without this change.

### Recommended
The workflow may work without this change, but modifying it improves correctness, maintainability, or architecture isolation.

### Verify
The workflow contains something that may be architecture-sensitive, but repository evidence is insufficient to determine whether a change is required.

### No Change
The workflow component is architecture-neutral and does not need modification.

---

# Output Format

The skill must generate a Markdown file with the following structure.

```markdown
# ppc64le GitHub Actions Support Guide

## 1. Objective

Explain the goal of adding ppc64le support.

Target runner:

`ubuntu-24.04-ppc64le`

## 2. Workflow Analyzed

| Workflow | File | Relevant Job |
|---|---|---|
| CI | `.github/workflows/ci.yml` | `test` |

## 3. Current Workflow Structure

Briefly explain the relevant jobs, matrices, dependencies, and setup.

## 4. Recommended Implementation

Clearly state:

- Matrix addition OR separate job
- Why this approach is preferred
- Which job should be modified
- Which runner should be used

## 5. Required Changes

For every required change:

### Change 1 — <description>

**File**

```text
.github/workflows/ci.yml
```

**Location**

Identify the job/step/matrix section.

**Current behavior**

Explain what the workflow currently does.

**Required change**

Explain what needs to change for ppc64le.

**Suggested implementation**

Provide a minimal YAML or shell snippet where useful.

**Reason**

Explain why the change is necessary.

---

## 6. Installation / Setup Changes

Document architecture-specific installation requirements.

Include:

* package installation
* dependency installation
* binary downloads
* setup actions
* compiler/toolchain
* Python/Node/Go/Rust/etc. setup

---

## 7. Architecture-Specific Logic

Document:

* existing architecture detection
* x86 assumptions
* conditions
* environment variables
* required ppc64le branches

---

## 8. Matrix Changes

If applicable, show the recommended matrix structure.

Explain:

* new matrix entries
* `include`
* `exclude`
* potential matrix expansion

---

## 9. Cache and Artifact Considerations

Document any architecture-related concerns.

If none exist:

> No architecture-specific cache or artifact changes appear necessary.

---

## 10. Third-Party Action Considerations

List potentially architecture-sensitive actions.

For each:

* action
* reason for concern
* verification required

Do not make unsupported compatibility claims.

---

## 11. External Dependencies / Blockers

List things outside the workflow that may prevent ppc64le support.

Examples:

* dependency has no ppc64le wheel
* binary release does not publish ppc64le
* third-party action may not support ppc64le
* external package repository unavailable

Clearly distinguish blockers from workflow changes.

---

## 12. Change Summary

| File                       | Location             | Change                        | Priority |
| --------------------------- | --------------------- | ------------------------------ | -------- |
| `.github/workflows/ci.yml` | `jobs.test.runs-on`  | Add ppc64le runner            | Required |
| `.github/workflows/ci.yml` | `jobs.test.steps[3]` | Add ppc64le installation path | Required |

---

## 13. Validation Plan

Provide commands/checks that should be performed after implementing the changes.

Examples:

```bash
uname -m
```

Expected:

```text
ppc64le
```

Also describe:

* workflow dispatch/test strategy
* relevant job to execute
* installation validation
* build validation
* test validation
* artifact validation

---

## 14. Final Recommendation

Give a concise implementation recommendation.

Example:

> Add `ppc64le` through the existing matrix because the job is architecture-independent apart from the runner and dependency installation. Add an `include` entry for `ubuntu-24.04-ppc64le`, update the architecture-sensitive installation step, and make the cache key architecture-aware.
```

---

# Important Rules

## Rule 1 — Workflow Only
The analysis must remain focused on GitHub Actions. Do not turn the output into a general ppc64le porting guide.

## Rule 2 — Do Not Blindly Add a Matrix Dimension
Before recommending a matrix dimension, determine whether it would unintentionally multiply existing combinations. Prefer a targeted `include` entry when appropriate.

## Rule 3 — Do Not Blindly Create a Separate Job
A separate ppc64le job should only be recommended when there is a meaningful difference between the existing workflow and the ppc64le workflow.

## Rule 4 — Do Not Assume Every Dependency Needs Modification
Only flag dependencies when the workflow provides evidence of architecture sensitivity.

## Rule 5 — Do Not Invent URLs
Never invent ppc64le package repositories, download URLs, wheel URLs, release assets, or GitHub Actions versions. If the correct value cannot be determined, mark it as requiring validation.

## Rule 6 — Preserve Existing Workflow Design
The recommendation should make the smallest reasonable change to the existing workflow. Prefer minimal change + existing workflow conventions + explicit architecture handling over rewriting the workflow.

## Rule 7 — Reuse Existing Patterns
If the repository already has ARM support, architecture-specific installation, matrix-based architecture handling, or architecture-specific conditions, use those patterns as the primary reference for ppc64le support.

## Rule 8 — Distinguish Required From Optional
Every recommendation must clearly indicate whether it is Required, Recommended, Verify, or No Change.

## Rule 9 — Explain the "Why"
Do not merely say "Add ppc64le to the matrix." Explain the reasoning behind the choice.

## Rule 10 — Provide Minimal Snippets
When showing changes, provide only the relevant section instead of reproducing an entire large workflow.

---

# Final Quality Checklist

Before generating the Markdown guide, verify:

* [ ] All workflow files have been inspected.
* [ ] Relevant jobs have been identified.
* [ ] Existing matrices have been analyzed.
* [ ] `runs-on` configuration has been analyzed.
* [ ] `if:` conditions have been analyzed.
* [ ] Architecture-specific shell logic has been analyzed.
* [ ] Installation/setup steps have been analyzed.
* [ ] Binary downloads have been checked.
* [ ] Package installation has been checked.
* [ ] Cache keys have been checked.
* [ ] Artifact names have been checked.
* [ ] Third-party actions have been identified.
* [ ] Existing architecture support patterns have been considered.
* [ ] Matrix vs separate-job decision has been justified.
* [ ] Required changes are separated from recommendations.
* [ ] Unknown compatibility issues are marked as `Verify`.
* [ ] No unsupported assumptions have been presented as facts.
* [ ] The output remains focused exclusively on GitHub Actions.
* [ ] A validation plan is included.
* [ ] The final recommendation is concise and actionable.

# Expected Behavior

When this skill is invoked against a repository's GitHub Actions workflows, it should behave like a **CI workflow reviewer specializing in ppc64le enablement**.

It should answer:

> "Exactly where in these GitHub Actions workflows do I need to make changes so this project can run its CI on `ubuntu-24.04-ppc64le`, and what should those changes look like?"

The result should be a practical Markdown implementation guide that another engineer can follow to make the workflow changes.
 