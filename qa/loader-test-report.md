# Web loader transport tests

Date: 2026-11-07. Test runner: `scripts/test-web-loader.mjs`.

## Final result

**PASS: 14 cases, 260 assertions, zero failures, exit code 0.**

Final run: 2026-11-07 17:05:57 UTC (20:05:57 Moscow), Node v24.22.1, approximately 1.25 seconds. The corrected built export was tested without modifying the owner HTML/build files.

| Tested artifact | SHA-256 |
| --- | --- |
| `dist/index.html` | `b54cce2778230c1058c6a11f9d1059847d43b9005820421a07df9eeb850758d8` |
| `dist/index.pck` | `f35e5f66679252b0522f565fd11e6752b129ede1570af11028d48649a9cfb43a` |
| Reconstructed WASM | `26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6` |

All 16 deployed files are within the 25 MiB individual-file ceiling. The largest is `engine-part-1.bin`, 20,971,520 bytes. Total export size is 47,872,401 bytes, including raw fallback and gzip representations; a normal gzip-path launch does not download the raw parts. The runtime gzip asset is 9,504,022 bytes and reconstructs the original 37,700,666-byte engine.

## What is tested

The runner executes the actual generated inline loader from `dist/index.html` in a Node `vm`. DOM elements, the Godot `Engine` interface, `fetch`, and timers are mocked. Exported gzip/raw runtime files, the manifest, game-pack bytes, Web Streams, decompression, and SHA-256 checks are real. The fetch mock reads only the local export directory; the test performs no network request.

**This is not a browser, WebGL, rendering, performance, or actual Godot engine execution test.** No browser workaround was attempted. The main agent observed that the cloud browser does not expose WebGL 2, so its compatibility-message path is the only browser behavior established there so far.

Run from the project directory:

```bash
node --expose-gc scripts/test-web-loader.mjs
```

The optional garbage-collection flag limits retained test buffers between cases; normal `node scripts/test-web-loader.mjs` also works. Each run reports the exact built-HTML hash, runtime identity, asset sizes, individual cases and assertion count, returning a nonzero exit code on failure.

## Coverage

1. Every deployed file is at most 25 MiB; the oversized original is absent.
2. Both raw parts match their expected sizes/hashes; concatenation matches the original WASM.
3. Gzip size/hash and actual decompression match the same original bytes.
4. Normal gzip loading reveals the mocked canvas only after successful mock initialization.
5. Without `DecompressionStream`, a real `Request` input takes the raw fallback.
6. Non-WASM, other-origin and HEAD requests bypass the adapter unchanged.
7. Same-length corruption, truncation and an oversized response are rejected.
8. Missing second part, missing manifest and a midstream reader error show a reload action.
9. The complete reconstructed runtime hash is checked before delivering a synthetic response.
10. A missing `Engine` script and unavailable WebGL have explicit outcomes.
11. A simulated startup timeout clears progress and exposes recovery; a late resolution cannot dismiss that error.
12. Failure cancels the runtime download signal; success and failure restore native fetch.

## First run against the prior export

Node v24.22.1, 2026-11-07 17:03:18 UTC. Built HTML SHA-256: `3ff2ac187354d23b022dc82ea415f69900ec8e892b5c3e2f65803e55bf6153ed`.

Four of fourteen cases passed: the asset audit, actual gzip route, raw fallback, and adapter pass-through. Ten cases failed on fixes already present in the owner's source shell but not yet re-exported: native fetch restoration on failure/unsupported capabilities, and the missing-Engine guard. These failures were reported to the owner. This is deliberately retained as evidence that the harness detects the old failure paths, not a final release result.

Observed asset evidence:

| Item | Bytes |
| --- | ---: |
| Original WASM | 37,700,666 |
| Explicit gzip asset | 9,504,022 |
| Raw part 1 / largest static asset | 20,971,520 |
| Raw part 2 | 16,729,146 |
| All 14 static assets in this export | 47,769,597 |

Both delivery representations reconstruct WASM SHA-256 `26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6`.

The owner re-exported the corrected shell; the subsequent final run above passes the same suite. A pass still does not replace a supported-browser gameplay check or phone testing. Hosted response headers, browser compilation/rendering and real mobile performance remain outside these Node tests.
