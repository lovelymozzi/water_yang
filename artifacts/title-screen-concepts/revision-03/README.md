# WATER MEOW title concepts — revision 03

2026-11-15. Additional title-screen proposals requested after revision 02 A was preferred. Preserve its simple dimensional toon style and include the established child scientist in two alternatives.

- **A — 둥둥 쉼터:** Three sleepy cats drift around a grassy island.
- **B — 박사의 관찰 노트:** The scientist sits on the bank and records observations while cats float past.
- **C — 풍덩! 첫 만남:** The surprised scientist lands in the stream; nearby cats remain relaxed.

## References and scope

Style master: `../revision-02/a-lobby-toon-generated.png`. The generation input `style-and-scientist-reference.jpg` combines style and established scientist references. Individual UTF-8 prompts and gateway result metadata accompany each generated image.

These are offline generated proposals, not game screenshots or renders of the game's actual meshes. No runtime assets, contracts, gameplay, camera, or scene flow were changed for these proposals.

## Preview method and inspection

Source images are 1024×1536 (2:3). Preview images uniformly resize the entire source to 786×1179, then overlay the existing splash contract's loading-bar artwork for context. All source artwork retains its original proportions and full frame. These previews do not claim to represent the current game's narrower viewport. Final production adaptation will require a composition fitted to that viewport.

Inspected all generated images and the final `comparison.jpg`: all three logos are readable; scientist and cats remain inside the frame; loading bars occupy the lower foreground. The B concept has a pencil in each hand. In C, the white shapes above the head are hair tufts; the scientist has two visible arms. Generated anatomy and style remain subject to art direction at final selection.

## Generation usage

Model: `gpt-image-2.5-sunburst`, quality `low` (concept drafts). Route: Sunburst skill `scripts/generate_image.py` via Flava. Three successful requests; no retries.

Aggregate input text: 2,975 tokens; input image: 4,608 tokens; output image: 474 tokens. Estimated cost: USD 0.0329795 / KRW 46.17 at the skill's fixed USD 1 = KRW 1,400. Exact request results and totals are in `usage-summary.json`; artifact dimensions and hashes are in `asset-manifest.json`.
