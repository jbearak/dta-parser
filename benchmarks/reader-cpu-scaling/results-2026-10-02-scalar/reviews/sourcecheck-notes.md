# Metadata source-resolution candidate

This private variant changes only metadata_proxy_source in metadata-proxies.c, relative to measured candidate-gather4-v2. It reads data1 once, checks TYPEOF once, and reads XLENGTH at most once. A two- or three-slot VECSXP state still supplies element zero; every other representation still uses data1 directly. The three-slot synchronization condition and all synchronization statements are otherwise unchanged. metadata_proxy_state, scalar forwarding, retained caching, bulk APIs, ownership and constructors are unchanged.

The compiled helper shrinks from 76 to 62 assembly lines. Static code sites for XLENGTH fall from three to one; dynamically, ordinary two-slot state resolution saves one length call, and three-slot resolution saves two. The legacy direct-source path also avoids a second data1 fetch. The exact compiled assembly is retained for review; these structural reductions are not a timing claim.

The recorded package build passed and its source/installed receipt was reverified after the focused scalar tests. All 132 focused assertions pass, including copy isolation, materialized states, live three-slot missing-count changes, source materialization/GC and callback metadata. Exact counts and hashes are in sourcecheck-validation.json. Production source was not edited, and no benchmarks were run by this agent.
