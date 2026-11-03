# Better Resource Manager — attribution

Better Resource Manager (BRM) is a fork of **Adaptive Smart Manager** by
guardipee14 (https://github.com/guardipee14/Adaptive-Smart-Manager, MIT).

Adaptive Smart Manager combines and modifies the Smart Thread Manager and
Smart GPU Manager code originally published by **kuuk / Omisse** in
`ul-stmmod` (https://github.com/Omisse/ul-stmmod, MIT).

The original player-facing concepts and distribution modes are preserved:
Ratio, Demand, Graph, chaining, and the count/count-per-second toggle.

Adaptive Smart Manager added a shared implementation, defensive bug fixes,
cleaner registration/version handling, Upload Labs 3.0 demand detection and
a read-only compatibility surface for Adaptive Auto Connector.

Better Resource Manager adds Better Resource Hub (pooled CPU/GPU with
extensible ports), a shared allocator with an Auto mode, legacy scene path
aliases for existing saves, French translations and new test suites.
