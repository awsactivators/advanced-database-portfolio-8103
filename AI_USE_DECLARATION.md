# AI Use Declaration

The assessment brief (section 11) requires this declaration wherever AI tools were used.

1. **AI tool used:** Claude Sonnet 5.5
2. **What I used it for:** I used this AI tool to generate the synthetic data, fine tuned the codes and scripts, correct errored commands, and updated all documentation appropriately.
3. **How I reviewed, corrected, tested and verified the output:**
   * I installed PostgreSQL, Redis, Python, Graphviz and the MongoDB tools myself and ran every script on my own Mac. The logs and screenshots in my evidence folders come from my own runs.
   * I replaced the figures in the first drafts with my own results, including my query timings, Redis timings, partition counts and replication lag.
   * Where my results differed from the first drafts I changed the text to match what I observed. For example, Q2 and Q3 did not get faster after indexing, so I rewrote those comments and explained why using the execution plans.
   * I ran the concurrency demo twice. The buyer who lost in experiment C changed between runs (buyer 0 first, buyer 1 second), while the same session was aborted in the deadlock test both times, and I wrote this into the limitations.
   * I fixed my own setup problems with the tool's guidance: a broken `.zshrc`, and the Atlas `collMod` error, which needed the `dbAdmin` role for my database user.
   * I checked the technical claims against the official documentation listed in `REFERENCES.md`.

I remain responsible for the accuracy, originality and understanding of everything I have submitted.
