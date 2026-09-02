# ppc64le GitHub Actions Support Guide

## 1. Objective

Enable XGBoost CI to run Python tests and build Python CPU wheels on the IBM Power (ppc64le) architecture.

Target runner:

```text
ubuntu-24.04-ppc64le
```

This guide covers two independent goals:

| Goal | Relevant Workflow | Relevant Job |
|---|---|---|
| Run Python tests on ppc64le | `main.yml` | `test-python-wheel-cpu` |
| Build a ppc64le CPU wheel (`xgboost-cpu`) | `main.yml` | `build-python-wheels-cpu` |

---

## 2. Workflows Analyzed

| Workflow | File | Jobs Inspected |
|---|---|---|
| XGBoost CI | `.github/workflows/main.yml` | `build-python-wheels-cpu`, `test-python-wheel-cpu`, `build-cpu`, matrices for `build-cuda`, `audit-cuda-wheel` |
| Python tests | `.github/workflows/python_tests.yml` | `python-sdist-test`, `python-system-installation-on-ubuntu` |
| CI configure (reusable) | `.github/workflows/ci_configure.yml` | `ci-configure` |
| Pipeline scripts | `ops/pipeline/build-python-wheels-cpu.sh`, `ops/pipeline/test-python-wheel.sh` | — |

---

## 3. Current Workflow Structure

```text
XGBoost CI (main.yml)
├── ci-configure          (AWS ECR login + image tag; runs on linux-amd64-cpu)
├── build-cpu             (matrix: default, sanitizer; linux-amd64-cpu, Docker container)
├── build-cuda            (matrix: x86_64 + aarch64 × CUDA 12/13; GPU build)
├── audit-cuda-wheel      (matrix: x86_64 + aarch64 × CUDA 12/13)
├── build-python-wheels-cpu   ← KEY TARGET for wheel generation
│    └── matrix: manylinux_2_28 × {aarch64, x86_64}
│        runner: {linux-arm64-cpu, linux-amd64-cpu}
│        calls: ops/pipeline/build-python-wheels-cpu.sh <target> <arch>
├── test-python-wheel-cpu     ← KEY TARGET for Python tests
│    └── matrix: {CPU-amd64, CPU-arm64}
│        runner: {linux-amd64-cpu, linux-arm64-cpu}
│        calls: ops/pipeline/test-python-wheel.sh --suite {cpu, cpu-arm64}
└── (GPU test/build jobs — out of scope for ppc64le initially)

Python tests (python_tests.yml)
├── python-sdist-test         (matrix: macos-15-intel, windows-latest, ubuntu-latest)
└── python-system-installation-on-ubuntu  (ubuntu-latest, sccache-based)
```

The `build-python-wheels-cpu` job already follows an `include`-based matrix pattern for amd64 and aarch64. The `test-python-wheel-cpu` job mirrors the same pattern. These are the natural extension points for ppc64le.

---

## 4. Recommended Implementation

**Recommendation: Separate job (not matrix addition)**

Rationale:

1. **Docker image dependency** — Both `build-python-wheels-cpu` and `test-python-wheel-cpu` rely on a project-maintained Docker image pulled from a private AWS ECR registry (`xgb-ci.manylinux_2_28_<arch>`). A `manylinux_2_28_ppc64le` image does not currently exist in the registry. This is the primary blocker. Until that image is created, a matrix entry cannot simply be added.

2. **`build-python-wheels-cpu.sh` uses `docker_run.py`** — The script internally calls `ops/docker_run.py` and `auditwheel`, both of which invoke the Docker image by URI. Adding `ppc64le` to the matrix without a matching Docker image would fail at this step.

3. **`test-python-wheel.sh` does not have a `cpu-ppc64le` suite** — The validation logic in `test-python-wheel.sh` explicitly allows only `{gpu, mgpu, gpu-arm64, cpu, cpu-arm64}`. A new `cpu-ppc64le` case must be added.

4. **`python-sdist-test` in `python_tests.yml`** — This job does have a runner-agnostic setup (miniforge + sccache + sdist build). It is a candidate for a matrix addition with minimal friction and should be treated separately below.

A separate job makes the ppc64le path explicit, keeps the existing matrix clean, and avoids multiplying test combinations until ppc64le is confirmed stable.

---

## 5. Required Changes

### Change 1 — Add `cpu-ppc64le` suite to `test-python-wheel.sh`

**File**

```text
ops/pipeline/test-python-wheel.sh
```

**Location**

Lines 27, 35, 41, 44, 51, 77, 130 — the `suite` validation and case blocks.

**Current behavior**

The script accepts only `gpu`, `mgpu`, `gpu-arm64`, `cpu`, `cpu-arm64`. Any other value causes an immediate error exit.

**Required change**

Add `cpu-ppc64le` as a valid suite that runs the same reduced test set as `cpu-arm64` (subset of `tests/python`), at minimum for initial enablement. The ARM64 suite runs only:

```bash
tests/python/test_basic.py
tests/python/test_basic_models.py
tests/python/test_model_compatibility.py
```

This is appropriate for ppc64le as a starting point until full test coverage is validated.

**Suggested implementation**

```bash
# Line ~27 — update usage string
echo "Usage: $0 --suite {gpu|mgpu|gpu-arm64|cpu|cpu-arm64|cpu-ppc64le} [--cuda-version {12|13}]"

# Line ~35 — update error message
echo "Error: --suite is required (gpu, mgpu, gpu-arm64, cpu, cpu-arm64, or cpu-ppc64le)"

# Line ~41 — update case pattern
gpu|mgpu|gpu-arm64|cpu|cpu-arm64|cpu-ppc64le)

# Line ~44 — update error message
echo "Error: --suite must be one of: gpu, mgpu, gpu-arm64, cpu, cpu-arm64, cpu-ppc64le. Got '${suite}'"

# Line ~77 — update activation case to include cpu-ppc64le
cpu|cpu-arm64|cpu-ppc64le)
    source activate linux_cpu_test
    ;;

# After the cpu-arm64 case block (~line 130) — add new case:
  cpu-ppc64le)
    echo "-- Run Python tests (CPU, ppc64le)"
    pytest -v -s -rxXs --durations=0 \
      tests/python/test_basic.py tests/python/test_basic_models.py \
      tests/python/test_model_compatibility.py
    ;;
```

**Reason**

Without this change, the `test-python-wheel.sh` script will reject the `cpu-ppc64le` suite argument with a validation error before any test runs.

---

### Change 2 — Add `build-python-wheels-cpu-ppc64le` job to `main.yml`

**File**

```text
.github/workflows/main.yml
```

**Location**

After the existing `build-python-wheels-cpu` job definition (line ~284).

**Current behavior**

`build-python-wheels-cpu` runs a matrix over `{aarch64, x86_64}` with runner labels `linux-arm64-cpu` and `linux-amd64-cpu`. It calls `ops/pipeline/build-python-wheels-cpu.sh manylinux_2_28 <arch>` inside a Docker container image pulled from `xgb-ci.manylinux_2_28_<arch>`.

**Required change**

Add a separate job that uses the `ubuntu-24.04-ppc64le` runner directly (no Docker container) and builds the wheel natively via `pip wheel` + `auditwheel` installed on the runner itself.

**Suggested implementation**

```yaml
  build-python-wheels-cpu-ppc64le:
    name: Build CPU wheel (xgboost-cpu) for manylinux_2_28_ppc64le
    runs-on: ubuntu-24.04-ppc64le
    steps:
      - uses: actions/checkout@v7.0.1
        with:
          submodules: "true"
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install build dependencies
        run: |
          pip install --upgrade pip wheel auditwheel build pydistcheck scikit-build-core cmake ninja
      - name: Patch package name to xgboost-cpu
        run: python3 ops/script/pypi_variants.py --use-suffix=cpu --require-nccl-dep=na
      - name: Build wheel
        run: |
          cd python-package
          python -m pip wheel --no-deps -v . --wheel-dir dist/
      - name: Audit wheel
        run: |
          auditwheel repair --only-plat \
            --plat manylinux_2_28_ppc64le python-package/dist/xgboost_cpu-*.whl \
            --wheel-dir wheelhouse/
          python3 -m wheel tags --python-tag py3 --abi-tag none \
            --platform manylinux_2_28_ppc64le --remove wheelhouse/xgboost_cpu-*.whl
          rm -v python-package/dist/xgboost_cpu-*.whl
          mv -v wheelhouse/xgboost_cpu-*.whl python-package/dist/
      - name: Verify libgomp is vendored
        run: |
          if ! unzip -l ./python-package/dist/*.whl | grep libgomp > /dev/null; then
            echo "error: libgomp.so was not vendored in the wheel"
            exit 1
          fi
      - name: Check wheel size
        run: pydistcheck --config python-package/pyproject.toml python-package/dist/*.whl
      - name: Upload wheel artifact
        uses: actions/upload-artifact@v7.0.1
        with:
          name: python-wheel-manylinux_2_28_ppc64le
          path: python-package/dist/*.whl
          retention-days: 7
```

**Reason**

The existing `build-python-wheels-cpu.sh` uses `ops/docker_run.py` to invoke a private AWS ECR container image (`xgb-ci.manylinux_2_28_ppc64le`) that does not yet exist. Running natively on the `ubuntu-24.04-ppc64le` runner avoids this dependency and mirrors how the `python-sdist-test` job already builds from source without a container. The native build produces a `manylinux_2_28_ppc64le` wheel tag via `auditwheel`.

---

### Change 3 — Add `test-python-wheel-cpu-ppc64le` job to `main.yml`

**File**

```text
.github/workflows/main.yml
```

**Location**

After the existing `test-python-wheel-cpu` job definition (line ~545).

**Current behavior**

`test-python-wheel-cpu` has a matrix of `{CPU-amd64, CPU-arm64}` with Docker containers pulled from `xgb-ci.cpu` and `xgb-ci.cpu_aarch64`. It downloads the wheel via S3 artifact stash (`RUNS_ON_S3_BUCKET_CACHE`) and runs `test-python-wheel.sh`.

**Required change**

Add a separate job depending on `build-python-wheels-cpu-ppc64le` that downloads the wheel from the GitHub Actions artifact uploaded in Change 2 and runs the `cpu-ppc64le` suite.

**Suggested implementation**

```yaml
  test-python-wheel-cpu-ppc64le:
    name: Python tests CPU (ppc64le)
    needs: build-python-wheels-cpu-ppc64le
    runs-on: ubuntu-24.04-ppc64le
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v7.0.1
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Download ppc64le wheel artifact
        uses: actions/download-artifact@v4
        with:
          name: python-wheel-manylinux_2_28_ppc64le
          path: wheelhouse
      - name: Install test dependencies
        run: pip install pytest numpy scipy
      - name: Run Python tests (CPU, ppc64le)
        run: bash ops/pipeline/test-python-wheel.sh --suite cpu-ppc64le
```

**Reason**

The existing `test-python-wheel-cpu` job depends on `ci-configure` and `audit-cuda-wheel` (the S3 stash system). Since the ppc64le wheel is built in a separate job that does not use the S3 stash, the test job must download from the GitHub Actions artifact uploaded in Change 2. No container image is needed.

---

### Change 4 — Add `ubuntu-24.04-ppc64le` to `python-sdist-test` matrix

**File**

```text
.github/workflows/python_tests.yml
```

**Location**

`jobs.python-sdist-test.strategy.matrix.os` (line 28).

**Current behavior**

```yaml
matrix:
  os: [macos-15-intel, windows-latest, ubuntu-latest]
```

**Required change**

```yaml
matrix:
  os: [macos-15-intel, windows-latest, ubuntu-latest, ubuntu-24.04-ppc64le]
```

**Reason**

This job installs XGBoost from the source distribution (`pip install ./dist/xgboost-*.tar.gz`) entirely from source with no Docker container and no architecture-specific binary dependencies in the workflow steps. The only potential friction is the `sccache` action (see Section 10). If sccache is unavailable on ppc64le, the `sccache --show-stats` step will fail — that step can be conditioned or removed for ppc64le.

**Priority: Recommended** — This is a lower-risk addition and provides early validation of the C++ build system on ppc64le before the full wheel pipeline is established.

---

## 6. Installation / Setup Changes

### Native runner (Changes 2, 3)

On `ubuntu-24.04-ppc64le`, the following system packages are required for the C++ build:

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build libgomp1 git
```

These are typically pre-installed on GitHub-hosted Ubuntu runners but should be verified for the ppc64le runner image.

Python build tools:

```bash
pip install --upgrade pip wheel auditwheel build pydistcheck scikit-build-core cmake ninja
```

`auditwheel` on ppc64le will recognize `manylinux_2_28_ppc64le` as the platform tag when running on Ubuntu 24.04 (glibc 2.39 ≥ 2.28). Verify this assumption:

```bash
auditwheel show python-package/dist/*.whl
```

Expected output should contain `manylinux_2_28_ppc64le`.

### `miniforge-setup` action (Change 4 — sdist test)

The `python-sdist-test` job uses `dmlc/xgboost-devops/actions/miniforge-setup@main`. This action installs Miniforge (conda). **Verify** that this third-party action supports ppc64le runners (see Section 10).

If Miniforge setup fails, fall back to `actions/setup-python@v5`:

```yaml
# Alternative to miniforge-setup
- uses: actions/setup-python@v5
  with:
    python-version: "3.12"
```

---

## 7. Architecture-Specific Logic

### `test-python-wheel.sh` — suite validation (blocker)

The script at `ops/pipeline/test-python-wheel.sh` explicitly allows only:

```bash
gpu|mgpu|gpu-arm64|cpu|cpu-arm64
```

`ppc64le` is not listed. This will cause an immediate error exit before any test runs. **Change 1 above is required.**

### `build-python-wheels-cpu.sh` — `docker_run.py` usage (blocker)

The script calls `ops/docker_run.py` to run the build inside the `xgb-ci.manylinux_2_28_${arch}` image. The `arch` value is positional argument `$2`. There is no ppc64le Docker image in the registry. This script cannot be used as-is for ppc64le. The native build approach in Change 2 bypasses this entirely.

### `build-cpu.sh` — sanitizer path assumption

```bash
-DSANITIZER_PATH=/usr/lib/x86_64-linux-gnu/
```

This is only in the `sanitizer` matrix variant and is not needed for the initial ppc64le Python test/wheel scope. **No Change required** for the Python test/wheel goal.

### Cache keys — `sccache`

The existing jobs that use `dmlc/xgboost-devops/actions/sccache@main` pass a `cache-key-prefix` parameter. The cache key does not include architecture. If the same prefix were used on ppc64le runners, cached amd64 compiler artifacts could be served to ppc64le, causing a corrupt build. The new ppc64le jobs proposed in this guide do **not** use sccache, so this is **No Change** for the proposed jobs. If sccache is added to ppc64le jobs later, use a distinct prefix:

```yaml
cache-key-prefix: build-ppc64le-cpu
```

---

## 8. Matrix Changes

### `python-sdist-test` — matrix addition (Change 4)

Before:

```yaml
strategy:
  matrix:
    os: [macos-15-intel, windows-latest, ubuntu-latest]
```

After:

```yaml
strategy:
  matrix:
    os: [macos-15-intel, windows-latest, ubuntu-latest, ubuntu-24.04-ppc64le]
```

**Matrix expansion implication:** This adds 1 job (from 3 → 4). It does not affect the `macos` extra step because it is already conditioned on `matrix.os == 'macos-15-intel'`. No other matrix explosion risk.

### `build-python-wheels-cpu` — no matrix change

The `manylinux_2_28_ppc64le` Docker image does not exist yet. Do not add `ppc64le` to the existing matrix. Use the separate job (Change 2) instead.

### `test-python-wheel-cpu` — no matrix change

This job depends on `audit-cuda-wheel` and uses the S3 artifact stash system tied to the `runs-on` infrastructure. The ppc64le job uses a different artifact delivery mechanism (GitHub Actions artifacts). Use a separate job (Change 3) instead.

---

## 9. Cache and Artifact Considerations

### Artifact naming

Change 2 uploads the ppc64le wheel as:

```yaml
name: python-wheel-manylinux_2_28_ppc64le
```

This is distinct from existing artifacts (`python-wheel-macosx_x86_64`, `python-wheel-macosx_arm64`) and will not collide.

### S3 artifact stash

The `RUNS_ON_S3_BUCKET_CACHE` S3 stash used by the existing `build-python-wheels-cpu` and `test-python-wheel-cpu` jobs is tied to the `runs-on` infrastructure label system. The `ubuntu-24.04-ppc64le` runner may not have access to this bucket. The proposed ppc64le jobs use `actions/upload-artifact` / `actions/download-artifact` instead, avoiding this dependency entirely.

---

## 10. Third-Party Action Considerations

| Action | Used In | Concern | Verification Required |
|---|---|---|---|
| `dmlc/xgboost-devops/actions/miniforge-setup@main` | `python-sdist-test`, `test-python-wheel-macos` | Miniforge installer may not publish a ppc64le binary or the conda environment YAML may pull x86-only packages | **Verify**: check whether the action's installer step handles `ppc64le` |
| `dmlc/xgboost-devops/actions/sccache@main` | `python-sdist-test`, `build-python-wheels-cpu` | `sccache` prebuilt binary may not have a ppc64le release | **Verify**: check the sccache release assets at the pinned version |
| `actions/setup-python@v7.0.0` / `@v5` | New ppc64le jobs | GitHub-provided; JavaScript action; should support ppc64le runners | **Verify**: confirm `ubuntu-24.04-ppc64le` runner supports `actions/setup-python` |
| `actions/checkout@v7.0.1` | All jobs | JavaScript action; architecture-neutral | Low concern |
| `actions/upload-artifact@v7.0.1` | New ppc64le jobs | JavaScript action; architecture-neutral | Low concern |
| `actions/download-artifact@v4` | Test job | JavaScript action; architecture-neutral | Low concern |
| `aws-actions/amazon-ecr-login@v2.1.7` | `ci-configure` | Not used in new ppc64le jobs | Not applicable |

**Critical note on `miniforge-setup`:** If Miniforge cannot be installed on ppc64le, the `python-sdist-test` matrix entry for `ubuntu-24.04-ppc64le` will fail at setup. In that case, replace the `miniforge-setup` action with `actions/setup-python` and `pip install -r ops/conda_env/sdist_test.yml`-equivalent packages via pip.

---

## 11. External Dependencies / Blockers

### Blocker 1 — `xgb-ci.manylinux_2_28_ppc64le` Docker image does not exist

The current `build-python-wheels-cpu` job calls `ops/docker_run.py` with the image `xgb-ci.manylinux_2_28_${arch}`. A ppc64le-compatible version of this image must be created and pushed to the AWS ECR registry before this job can be used for ppc64le via the matrix path.

**Mitigation:** Change 2 proposes a native build on the ppc64le runner, bypassing the Docker image requirement entirely.

### Blocker 2 — `xgb-ci.cpu_ppc64le` Docker image does not exist

The `test-python-wheel-cpu` job uses `xgb-ci.cpu_aarch64` / `xgb-ci.cpu` images that include a pre-built conda environment (`linux_cpu_test`). A ppc64le equivalent image does not exist.

**Mitigation:** Change 3 uses the native runner with `pip install` to set up the test environment without a container.

### Blocker 3 — `linux_cpu_test` conda environment on ppc64le

`test-python-wheel.sh` calls `source activate linux_cpu_test` for `cpu` and `cpu-arm64` suites. This environment is provided by the Docker image. On the native runner, this `activate` call will fail.

**Mitigation:** Change 1 adds `cpu-ppc64le` as a new suite case that skips the conda activation and instead uses the system Python (installed via `actions/setup-python`). The test dependencies are installed directly via `pip install pytest numpy scipy` in the workflow job (Change 3).

### Potential Blocker 4 — `auditwheel` `manylinux_2_28_ppc64le` policy

`auditwheel` must recognize `manylinux_2_28_ppc64le` as a valid platform. This is supported in `auditwheel >= 4.0` with the `manylinux_2_28` policy for ppc64le. The `ubuntu-24.04` runner provides glibc 2.39, which satisfies the `manylinux_2_28` requirement.

**Requires validation:** Run `auditwheel show` on the built wheel to confirm the recognized platform tags before applying `--only-plat`.

### Potential Blocker 5 — Native extension dependencies

XGBoost's Python package includes a native shared library (`libxgboost.so`). The CMake build requires:

- A C++17-capable compiler (GCC ≥ 7 or Clang ≥ 5) — Ubuntu 24.04 provides GCC 13 ✓
- OpenMP (`libgomp`) — available as `libgomp1` via apt ✓
- `cmake >= 3.18` — available via pip or apt on Ubuntu 24.04 ✓

No ppc64le-specific CMake flags are expected to be needed for the CPU-only build (no CUDA, no GPU flags).

---

## 12. Change Summary

| File | Location | Change | Priority |
|---|---|---|---|
| `ops/pipeline/test-python-wheel.sh` | `suite` validation + case blocks | Add `cpu-ppc64le` suite | **Required** |
| `.github/workflows/main.yml` | New job after `build-python-wheels-cpu` | Add `build-python-wheels-cpu-ppc64le` job | **Required** |
| `.github/workflows/main.yml` | New job after `test-python-wheel-cpu` | Add `test-python-wheel-cpu-ppc64le` job | **Required** |
| `.github/workflows/python_tests.yml` | `jobs.python-sdist-test.strategy.matrix.os` | Add `ubuntu-24.04-ppc64le` | Recommended |
| `ops/pipeline/build-python-wheels-cpu.sh` | No change needed | Not used by ppc64le path | No Change |
| `ops/pipeline/build-cpu.sh` | Sanitizer path | Not in scope for Python test/wheel goal | No Change |
| Cache keys | `sccache` action | Not used in proposed ppc64le jobs | No Change |

---

## 13. Validation Plan

### Step 1 — Verify runner architecture

After the job starts on `ubuntu-24.04-ppc64le`, add a verification step:

```yaml
- name: Verify architecture
  run: uname -m
```

Expected:

```text
ppc64le
```

### Step 2 — Verify Python and pip

```bash
python --version
pip --version
```

Expected: Python 3.12.x, pip 24.x

### Step 3 — Verify wheel build

```bash
ls -la python-package/dist/
```

Expected: a `.whl` file with `ppc64le` in the name, e.g.:

```text
xgboost_cpu-3.x.x-py3-none-manylinux_2_28_ppc64le.whl
```

### Step 4 — Verify auditwheel platform recognition

```bash
auditwheel show python-package/dist/*.whl
```

Expected: output should list `manylinux_2_28_ppc64le` as a compatible platform.

### Step 5 — Verify libgomp vendoring

```bash
unzip -l python-package/dist/*.whl | grep libgomp
```

Expected: at least one `libgomp.so.*` entry.

### Step 6 — Verify test execution

The `test-python-wheel-cpu-ppc64le` job should produce:

```text
-- Run Python tests (CPU, ppc64le)
...
tests/python/test_basic.py - PASSED
tests/python/test_basic_models.py - PASSED
tests/python/test_model_compatibility.py - PASSED
```

### Step 7 — Verify sdist build (python_tests.yml)

The `python-sdist-test` matrix entry for `ubuntu-24.04-ppc64le` should complete with:

```bash
python -c 'import xgboost'
```

without error.

---

## 14. Final Recommendation

Implement the changes in this order:

1. **First (unblocked):** Add `cpu-ppc64le` to `test-python-wheel.sh` (Change 1). This is a pure script change with no infrastructure dependency.

2. **Second:** Add `ubuntu-24.04-ppc64le` to the `python-sdist-test` matrix in `python_tests.yml` (Change 4). This validates the C++ build from source before tackling the wheel pipeline, and has no Docker dependency.

3. **Third:** Add the `build-python-wheels-cpu-ppc64le` job to `main.yml` (Change 2) once Change 1 and the `auditwheel` platform tag are validated.

4. **Fourth:** Add the `test-python-wheel-cpu-ppc64le` job to `main.yml` (Change 3) once Change 2 produces a verified wheel.

> Add ppc64le support through **separate jobs** (not matrix additions) for the wheel build and test pipeline, because the existing jobs depend on private Docker images that do not yet have ppc64le equivalents. Use the `ubuntu-24.04-ppc64le` runner natively with `pip`-installed build tools and `auditwheel`. The `python-sdist-test` job in `python_tests.yml` is the safest first target as it builds from source with no container dependency.
