# PA2 Erlang: Distributed Log Analyzer

Group members: Kevin Zhu, Ryan Wang

Implemented features:

- Concurrent mode (empty `nodes.txt`): the Client, the Coordinator and all N
  Workers run as separate Erlang processes on the controller node.
- Distributed mode (`nodes.txt` has N lines): Worker `i` is spawned on node `i`;
  the Client and Coordinator stay together on the controller node.
- Initialization: the Client starts the Coordinator, which creates Workers
  `worker0` to `worker(N-1)` (stored in Worker-ID order, all active) and waits
  until every Worker reports ready. Only then does the Client read the script.
- Analyze: the Client reads the file and sends it to the Coordinator without
  waiting for the result. The Coordinator numbers the analysis (zero-based, in
  script order), takes a snapshot of the active Workers, splits the file into
  word-aligned chunks with `pa2_util:split_chunks/2` (one chunk per active
  Worker, sizes differ by at most one word) and sends them asynchronously. It
  stores the analysis in a map and returns to its receive loop immediately, so
  analyses overlap and later commands are accepted while earlier analyses are
  still collecting partial counts.
- Every chunk request and partial-count reply carries the analysis ID and chunk
  ID. The Coordinator adds each reply only to its own analysis, ignores
  duplicates, and sends exactly one final total to the Client once the last
  chunk of that analysis has returned.
- Empty or whitespace-only input produces no chunks and the result 0. If no
  Worker is active the result is `ERROR` and no chunk file is created; that
  analysis still uses its ID.
- Inactive: a barrier. The Coordinator marks the Worker inactive, tells it,
  waits for its acknowledgement and only then acknowledges the Client, which
  waits for that before reading the next command. Repeated deactivation has no
  further effect. The Worker stays alive (it keeps its ID, name and active
  state) and still completes every chunk of earlier analyses; it just receives
  no chunks from later ones.
- Workers save each chunk as `workers/worker<Id>/analysis<A>_chunk<C>.txt`
  and count case-sensitive, exact-word matches.
- The Client appends each result to the output file as soon as it arrives, in
  completion order, and at end of script waits for every outstanding result.
  It then stops the Coordinator, which stops the Workers, and run/4 returns.
- If the Coordinator or a Worker crashes, or a Worker node cannot be reached,
  the run ends with an error instead of hanging.

Known bugs: none known
