# Spike: Apple's sound classifier on bedroom audio (I2a)

Part of **I2 · Name the noise**. Question: is Apple's built-in sound classifier good enough to name the noises in a night's recording, and how should we run it?

> **Status: staged noise test done on the iPhone; one real night still to add.** A 20-sound test recording was classified straight from the file on a Mac and again after playing it through a speaker into the iPhone (below). The threshold and recommendations hold. A real night's sleep is still worth adding to see how the classifier handles quiet, distant noise.

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

## Staged noise test (23 Oct 2026)

`test-audio/noise-test.m4a` (not in the repo: its library clips are non-commercial) has 20 sounds, one a minute, over a faint room-noise floor. 15 are ESC-50 library recordings, 5 were made on a Mac (talking, TV, music, doorbell, door closing), and geese and sniffing use crow and breathing stand-ins. It was classified twice:

- **From the file** on a Mac (no speaker or microphone in between).
- **On the iPhone:** played from a speaker about a metre from the phone while Loop Sense recorded, then classified with the debug card.

| Sound | From the file | On the iPhone | Category on iPhone |
|---|---|---|---|
| Closing a door (synthesised) | music 0.74 ✗ | music 0.29 | Unknown |
| Talking | speech 0.94 | speech 0.89 | Speech ✓ |
| Cough | cough 0.99 | cough 0.97 | Speech ✓ |
| Music | music 0.92 | music 0.90 | Music/TV ✓ |
| Running a tap | water 0.74 | toilet_flush 0.82 | Household ✓ |
| Phone alarm | alarm_clock 0.85 | telephone_bell_ringing 0.90 | Alarm/Phone ✓ |
| Snoring | breathing 0.97 | snoring 0.76 | Snoring ✓ |
| Dog barking | coyote_howl 0.58 | dog 0.44 | Unknown (right label, below 0.5) |
| Rain outside | water 0.78 | water_tap_faucet 0.77 | Household ✗ |
| Wind outside | thunderstorm 0.59 | music 0.32 | Unknown |
| Birds singing | bird_chirp_tweet 0.97 | bird_vocalization 0.77 | Animals ✓ |
| Baby crying | babble 0.77 | laughter 0.69 | Speech ✓ |
| Knocking on the front door | knock 1.00 | knock 1.00 | Household ✓ |
| Doorbell | door_bell 0.85 | door_bell 0.98 | Alarm/Phone ✓ |
| Plane flying over | airplane 0.98 | snake_hiss 0.76 | Animals ✗ |
| Helicopter flying over | aircraft 0.77 | squeak 0.75 | Household ✗ |
| Geese (crow stand-in) | crow_caw 1.00 | crow_caw 0.93 | Animals ✓ |
| Television | music 0.96 | speech 0.91, music 0.90 | Speech (≈) |
| Sniffing (breathing stand-in) | gasp 0.98 | gasp 0.88 | Snoring ✓ |
| Toilet flushing | toilet_flush 1.00 | toilet_flush 1.00 | Household ✓ |

**On the iPhone: 13 of 20 in the right category, 1 close (TV as Speech), 3 Unknown, 3 wrong.**

- **Every sound was detected as a noise event.** The 3 extra events were setting up and stopping the recording, all with no label above 0.4.
- **Speed on the iPhone:** 20.6 minutes in 3.2 s (393× real time), so an 8-hour night takes about 75 seconds.
- **Short, distinct sounds survive the speaker and microphone well:** speech, cough, knock, doorbell, alarm, toilet flush, birds and crow all stayed at 0.77–1.00.
- **Broad, low rumbles don't:** plane, helicopter, wind and rain dropped from 0.6–0.98 to wrong or unsure labels. A small speaker can't reproduce their low frequencies, so this mostly shows the limits of the test. Real aircraft and weather outside a window still need checking on a real night.
- **Wrong answers can be confident:** `snake_hiss 0.76` for a plane and `squeak 0.75` for a helicopter both passed 0.5. A higher threshold wouldn't fix those, and it would lose correct labels like snoring at 0.76.
- **Category rules help:** the tap scored `toilet_flush` and the baby scored `laughter`, both wrong as labels but right as categories.

## Real nights

_Still to add: at least one real night recorded on the iPhone._

| Night | Length | Processing on iPhone | Events | Most common labels | Looks right? |
|---|---|---|---|---|---|
| | | | | | |
| | | | | | |
| | | | | | |

- Which labels come up (snoring, traffic, `air_conditioner`, `mechanical_fan`, ...)?
- How many top labels look correct when you play the event back?
- Any labels that are consistently wrong for a bedroom (e.g. `whale_vocalization`)?

## Provisional recommendations

- **Confidence threshold: 0.5.** Below this, call the noise "Unknown". In the noise test, false labels on silence stayed at or under 0.4 and correct labels were mostly 0.75–1.0. The one cost is the dog at 0.44, which became Unknown. Lowering to 0.4 would catch it but also let through the 0.40 setup noise, so 0.5 stays.
- **When to classify: after the night, from saved audio.** It's fast (about 75 seconds for an 8-hour night on the iPhone, measured), adds nothing to battery use overnight, and can be re-run if the classifier or rules change. Live classification during recording would only be needed for users who turn off **Save audio**. Consider that later, as a lighter "top label per event" pass.
- **Ranking for long events:** use the label that wins the most windows within the event, not its single highest score.
- **Treat aircraft, wind and rain labels with care** until a real night confirms them. They were the weakest through a speaker, and a wrong answer (for example a plane as `snake_hiss`) can still score above the threshold.
