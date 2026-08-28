# Search and Apple Intelligence

## Implemented domain layer

`BarlineCore` provides an in-memory deterministic index for menu bar items,
profiles, groups, commands, and help actions. Search normalizes case,
diacritics, width, and punctuation; removes common stop words; supports curated
synonyms, exact/prefix/substring/fuzzy matching, deterministic tie-breaking,
and a bounded recency bonus. Synchronization removes stale records by entity
kind.

Search records deliberately have no arbitrary metadata, file path, window
image, process inventory, or raw model-prompt field. Tests cover ranking,
synonyms, stale-record removal, availability planning, and typed command
validation. A small synthetic evaluation corpus covers ordinary, ambiguous,
unsupported, and malicious requests.

The app also contains a Core Spotlight adapter that replaces, upserts, and
removes a private Barline search domain. Its platform-neutral records bound
titles and keywords and expose only the closed search fields. Runtime probes
report actual Core Spotlight availability and Foundation Models
eligibility/readiness without creating a model session. The existing app search
panel now constructs bounded documents for live menu items and saved profiles,
uses the deterministic index for ranking, exposes profile activation results,
and replaces Barline's private Spotlight domain when the document set changes.

## Typed on-device interpretation

On macOS 26, ambiguous queries may enter a lazy `SystemLanguageModel` session.
The adapter uses `@Generable` with a closed operation enum, at most 20 targets,
and bounded privacy-safe documents. Generated IDs resolve against the supplied
context, then pass current authority, `MenuBarCommandValidator`, and confirmation
policy. Invalid, low-confidence, or unavailable-model results fall back to
deterministic search without mutation.

Evaluation routing requires at least 80% overall accuracy and 100% rejection of
unsafe requests before candidate evidence may pass.

## Remaining work

- Core Spotlight query/deep-link handling and user-facing reindex controls
- macOS 27 `SpotlightSearchTool`
- candidate-bound execution and recording of the model evaluation corpus

The App Intents extension implements stable-ID profile entity lookup against a
privacy-bounded App Group catalog. It does not read menu-bar snapshots or call
the compatibility helper.

The availability model always keeps deterministic local search enabled and can
plan optional Spotlight/model stages. Capability alone never authorizes a
command.

## Safety contract

Model output is decoded into a closed typed command, checked by
`MenuBarCommandValidator`, bound to the current generation and known entities,
and subjected to confirmation policy. The model cannot emit executable code,
paths, shell commands, or bypass deterministic validation. Search must remain
useful with Apple Intelligence disabled, unavailable, or unsupported, and no
query may be sent to a remote model.
