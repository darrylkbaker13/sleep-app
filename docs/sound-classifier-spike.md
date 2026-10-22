# Spike: Apple's sound classifier on bedroom audio (I2a)

Part of **I2 · Name the noise**. Question: is Apple's built-in sound classifier good enough to name the noises in a night's recording, and how should we run it?

> **Status: harness built, real nights still needed.** The results below come from two short test clips recorded in the Simulator (Mac microphone), not from real nights. Fill in the "Real nights" section after running the harness on at least 3 nights recorded on the iPhone, then revisit the threshold and recommendation.

## How to run it

**On the iPhone (Debug builds only):** open any night that has saved audio, scroll down, open **More detail** and tap **Run sound classifier** on the *Name the noises (debug)* card. Use **Share results** to send the text.

**On a Mac:** copy a night's `<id>.json` and `<id>.caf` from the app's `Documents/Sessions` folder (Xcode › Devices and Simulators › Loop Sense › Download Container), then:

```sh
tools/classify-night.sh path/to/<id>.json [more.json ...]
```

Both use the same code (`Loop Sense/SoundClassifier.swift`, `NightAnalysis.swift`), so their results match.

### What the harness does

- Runs `SNClassifySoundRequest(classifierIdentifier: .version1)` (303 labels) over the whole `.caf` with `SNAudioFileAnalyzer`. Default window is about 1 s with 50% overlap.
- For each noise event from `NightAnalysis` (10 dB or more above background), takes the windows overlapping the event (±0.5 s) and keeps each label's **highest** confidence, ignoring `silence`.
- Lists the top 3 labels per event, the most common winning label, and how long processing took.

## Early results (test clips, not real nights)

| Clip | Length | Processing | Events |
|---|---|---|---|
| 21 Oct, Simulator | 1.4 min | 0.3 s on Mac (274× real time) | 4 |
| 22 Oct, Simulator | 3.3 min | 0.5 s on Mac (439×), 0.9 s in Simulator (211×) | 4 |

What came out:

- **Clear single sounds are named confidently and correctly:** a door closing gave `door_slam 0.97, door 0.96`.
- **Speech is picked up well** (`speech` 0.53–0.89 on talking).
- **Long events collect odd labels.** A 51-second event scored `speech 0.89, screaming 0.86, whale_vocalization 0.81`. Taking each label's highest score over many windows lets one-off misfires rank high. For long events, ranking by **how many windows** a label wins (or its average confidence) should be more reliable than its peak.
- **Quiet events are unsure.** A 37 dB, 1-second blip scored no label above 0.17.

## Real nights

_To fill in after running on at least 3 iPhone nights:_

| Night | Length | Processing on iPhone | Events | Most common labels | Looks right? |
|---|---|---|---|---|---|
| | | | | | |
| | | | | | |
| | | | | | |

- Which labels come up (snoring, traffic, `air_conditioner`, `mechanical_fan`, ...)?
- How many top labels look correct when you play the event back?
- Any labels that are consistently wrong for a bedroom (e.g. `whale_vocalization`)?

## Provisional recommendations

- **Confidence threshold: 0.5** (provisional). Below this, call the noise "Unknown". The clear sounds above scored 0.7–0.97, and the quiet blip stayed under 0.2. Confirm on real nights.
- **When to classify: after the night, from saved audio.** It's fast (an 8-hour night should take roughly 1–2.5 minutes at the speeds above; to confirm on iPhone), adds nothing to battery use overnight, and can be re-run if the classifier or rules change. Live classification during recording would only be needed for users who turn off **Save audio**. Consider that later, as a lighter "top label per event" pass.
- **Ranking for long events:** use the label that wins the most windows within the event, not its single highest score.
