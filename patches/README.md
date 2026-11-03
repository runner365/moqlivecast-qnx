# Patches

Patches here are applied **on top of a pinned upstream commit** by
`scripts/bootstrap.sh`. Upstream is referenced by URL
(<https://github.com/runner365/moqlivecast>); its history is never copied in.

## Rules

1. One concern per patch: build system, then socket layer, then scheduling.
   Reviewers should be able to read `0001`-`000N` in order.
2. Every patch carries a body explaining *why* — what Linux assumption it
   removes and what QNX provides instead.
3. Regenerate against the pinned commit, never against a moving branch:

```bash
cd upstream
git format-patch -o ../patches --no-signature --cover-letter <pinned-sha>
# then delete the cover letter if you don't want it, and rewrite subjects
# to start with "qnx:" so the stack reads cleanly.
```

## Current stack

| # | subject | status |
|---|---|---|
| — | *(empty — first patch lands when the build is fixed)* | — |

## Planned first patches

1. `qnx: add CMAKE_SYSTEM_NAME QNX branch to the top-level CMakeLists`
2. `qnx: gate epoll/timerfd includes behind __QNX__ and use io-sock equivalents`
3. `qnx: route thread priorities through port/qnx/qnx_platform.h`
