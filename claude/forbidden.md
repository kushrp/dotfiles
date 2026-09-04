# Forbidden Patterns

A hit on this list is a defect, not a preference. Delete the match or rewrite the
sentence flat. Do not soften it and do not substitute a variant.

This file is the last gate before text ships. It catches machine-sounding prose
that survives the writing standards in `CLAUDE.md`.

## How to use it

1. Write the draft.
2. Reread it once for rhythm only. Look for symmetry first, because symmetry is
   the strongest tell. A sentence that sounds satisfying is usually a match below.
3. Delete each match.
4. Check the diction table.
5. Run the scan checklist at the bottom.

## Rhythm and rhetoric

### Staccato pairs

Two or three clipped fragments in a row, used for punch.

- Banned: "Ship it. Own it." / "No fluff. No filler." / "Small change. Big win."
- Instead: one full sentence that carries the information. "The change is two
  lines and it removes the retry loop."

### Antithesis reframe / negative parallelism

Defining a thing by rejecting a foil. Covers "not X, but Y", "isn't about X,
it's about Y", "less X, more Y", "X was never the problem".

- Banned: "This isn't a rewrite, it's a reset." / "The problem was never speed.
  It was trust."
- Instead: state the claim alone. "The migration replaces the retry loop with a
  queue."
- Exception: a real correction of something the reader said or believes. Say it
  once, plainly, then move on.

### Isocolon metaphor-pairs

Two images balanced at matching grammatical length and joined for symmetry.

- Banned: "Not a map, but a compass." / "The schema is the skeleton and the tests
  are the immune system."
- Instead: use one image, or none. Prefer none in technical writing.

### Backward-references

Sentences that point at earlier text instead of adding information. This includes
the closing callback that returns to the opening line.

- Banned: "That is the real story here." / "Which brings us back to where we
  started." / "As noted above," / "And that is why X matters."
- Instead: end on the last piece of new information. Cut the sentence.

### Rule-of-three padding

Three adjectives or clauses where one carries the meaning.

- Banned: "clear, concise, and compelling" / "faster, cheaper, and safer"
- Instead: keep the one that is true and measurable.

### Anaphora runs

Three or more sentences that open with the same word or structure, for cadence.

- Banned: "It handles retries. It handles backoff. It handles dead letters."
- Instead: one sentence with a list.

### Rhetorical question transitions

- Banned: "So what does this mean?" / "Why does this matter?" / "The question is:"
- Instead: write the answer as a statement.

### The reveal

Withholding the point for effect.

- Banned: "Here's the thing:" / "But there's a catch." / "This is where it gets
  interesting."
- Instead: lead with the point.

### Faux-profound drop

One short sentence alone on a line, placed to land as wisdom.

- Banned: "Context is everything." / "That is the whole game."
- Instead: delete it.

## Diction

Replace on sight. Do not reach for a synonym in the same register.

| Banned                                                  | Use instead            |
| ------------------------------------------------------- | ---------------------- |
| delve, dive into, unpack                                | read, check, explain   |
| leverage (as a verb)                                    | use                    |
| robust, seamless, powerful, elegant                     | say what it does       |
| landscape, ecosystem, tapestry, realm, journey          | the actual noun        |
| underscore, highlight (figurative), pivotal, crucial    | show, matter           |
| game-changing, revolutionary, transformative            | the measured effect    |
| truly, incredibly, remarkably, deeply, quite            | delete                 |
| it's worth noting that, it's important to note          | delete, keep the fact  |
| in today's world of, in an era of                       | delete                 |
| navigate (figurative), unlock, supercharge, empower     | the plain verb         |
| at the end of the day, ultimately                       | delete                 |
| not only X but also Y                                   | one clause for each    |
| perhaps, might, could possibly (when the fact is known) | state the fact         |

Also banned: every em dash (use a comma, a parenthesis, or a colon), and any
sentence whose only job is transition.

## Structure

- No sycophantic opener and no closing offer of more help. See the communication
  rules in `CLAUDE.md`, rule 10.
- No restating the request before answering it.
- No emoji in prose, commit messages, PR descriptions, or code comments unless
  the user asks for them.
- No bolding a full sentence for emphasis. Bold short labels only.
- No capability disclaimers and no "as an AI".
- No headers on a reply short enough to read without them.

## Scan checklist

Run these five checks on the draft:

1. Confirm that every sentence adds information the reader did not have one
   sentence earlier.
2. Find any pair or trio that is balanced for rhythm, then break it.
3. Confirm that the last sentence contains new information.
4. Search for each entry in the diction table.
5. Confirm the vocabulary and the one-idea-per-sentence rule meet ASD-STE100.
