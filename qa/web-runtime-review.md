# Godot web runtime delivery review

2026-11-07. Read-only review of the matching `4.6.3.stable/web_nothreads_release.zip` plus official browser/Godot documentation. No engine, build or application source was modified by this reviewer.

## Verdict

The proposed two-part WASM delivery is technically compatible with the unchanged Godot engine. It remains a real Godot/GDScript game: only transport of the identical engine bytes changes. Treat compatibility as a reviewed design until the actual exported game starts and plays in the target browser.

For the first prototype, prefer **fetching and validating both parts before resolving the intercepted WASM fetch**, then returning a synthetic `Response` with a Blob/ReadableStream body and `application/wasm`. There is a specific upstream error-propagation reason for this recommendation, described below. True progressive streaming is also possible but needs an explicit shell-level error path.

## Measured evidence

| Item | Observed value |
| --- | --- |
| Exact template WASM size | 37,700,666 bytes |
| WASM SHA-256 | `26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6` |
| Cloudflare documented per-static-asset limit | 25 MiB = 26,214,400 bytes |
| Same WASM compressed with `gzip -1` | 11,069,305 bytes |
| Matching template JS | `godot.js`, 315,759 bytes |

The gzip measurement was a cloud-only pipe, without installing packages or writing a replacement runtime. The full uncompressed WASM exceeds the hosting limit; two parts under 20 MiB each satisfy that individual-file constraint. Gzip is substantially smaller but is a different delivery option, not yet verified on this Site.

## Actual Godot 4.6.3 loader behavior

The installed template's `Preloader.loadFetch` calls ordinary global `fetch(file)`, checks `response.ok`, and passes the body through its own tracked `Response(new ReadableStream(...))`. `Engine.init` clones that response and hands it to `WebAssembly.instantiateStreaming`. The same code has an ArrayBuffer-based path when streaming instantiation is unavailable. Thus a standards-compliant synthetic response is an appropriate boundary; there is no need to patch Godot's generated engine JS.

**Important failure mode:** `getTrackedResponse` does not catch a rejection from its reader; `instantiateWasm` also attaches a success callback to `instantiateStreaming` without an error callback. A missing chunk detected before returning the response can reject the fetch normally. A failed second chunk discovered after the response has begun streaming may instead leave the launch promise/loading display unresolved unless the custom shell handles that failure itself.

Suggested first implementation:

1. Fetch the two parts with the captured native fetch; allow at most two concurrent downloads.
2. Require successful responses, expected byte counts and correct first-part WASM magic. Reject an authentication/HTML response even if the HTTP status is 200.
3. Only then resolve the intercepted request with a fresh response over `new Blob(parts).stream()`, carrying `Content-Type: application/wasm` and the total byte length.
4. Show progress while the two downloads happen. Godot's own progress may advance quickly after the synthetic response is released; label the separate preparation/engine-start phase honestly.

This trades download/compile overlap and some temporary memory for a simpler failure boundary. Blob concatenation avoids manually creating yet another 37.7 MB contiguous JavaScript array, although the browser and Godot still need runtime memory and this is not a zero-copy guarantee.

## Small implementation safeguards

- Install the wrapper before engine startup. Preserve a bound native `fetch` and call it unchanged for every unrelated request.
- Match the full resolved same-origin WASM URL and GET method, including `Request` inputs and `init.method`; do not intercept every `.wasm` URL or another origin.
- Generate ordered part names, sizes and hashes during the build. Hash-qualified filenames prevent a cached part from being combined with a different version. Verify concatenation equals the original SHA-256 during the build.
- Preserve same-origin credentials for the private Site. Forward an AbortSignal when provided and cancel outstanding part downloads on failure/navigation.
- Do not promise Range/HEAD handling: the shim is a narrow loader adapter. The standard Godot preload path observed here uses a normal GET.
- Do not retry indefinitely. The upstream preloader already has a bounded retry mechanism; present a reload action if launch ultimately fails.
- If progressive streaming is retained, on every reader/fetch/length error explicitly update the shell's error UI, error the stream and cancel remaining downloads. `engine.startGame().catch(...)` alone is insufficient for the observed upstream failure mode.
- Exclude the oversized original WASM only from deploy output. Keep export and deterministic splitting in the reproducible build; retain the measured hash in the build report.

## Comparison with gzip delivery

| Route | Benefit | Condition / tradeoff |
| --- | --- | --- |
| Two original-byte parts + loader adapter | No host-specific compression headers or decompression API; exact engine bytes retained | About 37.7 MB before any verified transport compression; two-part integrity/error logic |
| Precompressed `.wasm` served with correct `Content-Encoding: gzip` | About 11.1 MB in the measured file; native browser decompression and normal loader | Must verify Sites actually preserves the required header and MIME mapping; renaming bytes alone is insufficient |
| Explicit gzip asset + client `DecompressionStream('gzip')` | Can reduce transfer size without relying on custom response headers | Adds a browser API dependency and decompression/error handling; feature-detect and test before replacing the simple route |

For this bounded first delivery, the proposed chunk route is reasonable. Gzip is a worthwhile loading-time optimization after the actual hosting response behavior or client-decompression route is verified. No Android/SDK readiness follows from either method.

## Acceptance for the implemented adapter

### Subsequent source review

The owner's current implementation uses explicit gzip decompression when `DecompressionStream` exists and prebuffered raw parts otherwise. Both paths validate byte lengths and SHA-256 before returning the WASM response; a shell-level 120-second watchdog covers upstream initialization stalls. This incorporates the recommended pre-response validation boundary without changing the engine. Source inspection is not yet evidence of a successful hosted run.

The final Node `vm` transport test passes 14 cases / 260 assertions using real exported bytes: gzip and raw fallback, hashes/size limits, corrupted/truncated/oversized/body-reader errors, missing part/manifest, missing `Engine`, unavailable WebGL, and timeout with ignored late success. DOM/Engine/fetch are mocked; this does not prove browser compilation or rendering. The owner added the missing-Engine guard and restores native fetch on failure and unsupported capabilities. See `loader-test-report.md` for tested artifact hashes.

Remaining host checks: confirm the gzip URL returns compressed bytes (no unexpected server `Content-Encoding` auto-decoding) and run the actual game in a supported browser. The current fixed part/gzip names are integrity-checked, but hash-qualified names or explicit no-cache fetches would avoid stale-cache failures after a changed engine build. Total transfer memory and mobile browser performance still require real-device observation; narrow desktop emulation is not equivalent. The cloud browser lacks WebGL 2, and no policy workaround was attempted.

- [ ] Actual exported engine starts from parts with no request to a nonexistent original file.
- [x] Byte-for-byte concatenation matches the original WASM and every final export asset is below the host limit (Node audit; actual publication is separate).
- [x] A missing second part produces a visible mocked-DOM error, not an endless spinner; same-size gzip corruption also rejects before delivery.
- [ ] Normal PCK/JS/image fetches are untouched; private-Site credentials remain effective.
- [ ] Reload/cache reuse starts the same version, with no mixed-part build.
- [ ] Desktop and narrow-viewport gameplay both start and accept real input.

## Primary references

- Godot 4.6 export: https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html
- Godot 4.6 custom shell: https://docs.godotengine.org/en/4.6/tutorials/platform/web/customizing_html5_shell.html
- MDN `WebAssembly.instantiateStreaming`: https://developer.mozilla.org/en-US/docs/WebAssembly/Reference/JavaScript_interface/instantiateStreaming_static
- MDN `Response` constructor (ReadableStream accepted): https://developer.mozilla.org/en-US/docs/Web/API/Response/Response
- MDN `DecompressionStream`: https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream
- Cloudflare limits: https://developers.cloudflare.com/workers/platform/limits/

API support was checked against current primary documentation; the installed Godot template was inspected directly. Browser execution of the proposed adapter is still a separate acceptance step owned by the main agent.
