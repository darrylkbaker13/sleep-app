import Foundation

/// Plain-language groups for Apple's sound classifier labels (I2 · Name the noise).
/// This file is the single place that decides which label belongs where.
nonisolated enum NoiseCategory: String, CaseIterable, Identifiable {
    case snoring, speech, traffic, aircraft, animals, household, weather, musicTV, alarmPhone, other, unknown

    var id: String { rawValue }

    /// Below this confidence a label isn't trusted and the noise counts as Unknown.
    /// Provisional value from the I2a spike (docs/sound-classifier-spike.md); revisit after real nights.
    static let confidenceThreshold = 0.5

    var name: String {
        switch self {
        case .snoring: "Snoring"
        case .speech: "Speech"
        case .traffic: "Traffic"
        case .aircraft: "Aircraft"
        case .animals: "Animals"
        case .household: "Household"
        case .weather: "Weather"
        case .musicTV: "Music/TV"
        case .alarmPhone: "Alarm/Phone"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .snoring: "zzz"
        case .speech: "bubble.left.and.bubble.right.fill"
        case .traffic: "car.fill"
        case .aircraft: "airplane"
        case .animals: "pawprint.fill"
        case .household: "house.fill"
        case .weather: "cloud.rain.fill"
        case .musicTV: "music.note.tv.fill"
        case .alarmPhone: "alarm.fill"
        case .other: "waveform"
        case .unknown: "questionmark.circle"
        }
    }

    /// The category for a classifier label at a given confidence.
    /// Labels below the threshold, and "silence", count as Unknown; labels not listed below count as Other.
    static func category(for label: String, confidence: Double) -> NoiseCategory {
        guard confidence >= confidenceThreshold, label != "silence" else { return .unknown }
        return labelMap[label] ?? .other
    }

    /// Labels that say little on their own. "water" tops both a running tap and rain, so when one of
    /// these wins, a more specific label close behind it decides the category.
    static let vagueLabels: Set<String> = ["water", "click", "thump_thud", "whoosh_swoosh_swish"]

    /// The category for a noise from its top labels, most confident first.
    static func category(for labels: [(identifier: String, confidence: Double)]) -> NoiseCategory {
        let trusted = labels.filter { $0.confidence >= confidenceThreshold && $0.identifier != "silence" }
        guard let top = trusted.first else { return .unknown }
        if vagueLabels.contains(top.identifier),
           let specific = trusted.first(where: { !vagueLabels.contains($0.identifier) && labelMap[$0.identifier] != nil }) {
            return category(for: specific.identifier, confidence: specific.confidence)
        }
        return category(for: top.identifier, confidence: top.confidence)
    }

    /// Apple classifier label → category, built from the lists below.
    static let labelMap: [String: NoiseCategory] = {
        var map: [String: NoiseCategory] = [:]
        for (category, labels) in labels {
            for label in labels {
                assert(map[label] == nil, "\(label) is listed twice")
                map[label] = category
            }
        }
        return map
    }()

    /// Labels from SNClassifierIdentifier.version1, grouped. Anything not here is Other.
    static let labels: [NoiseCategory: [String]] = [
        .snoring: ["snoring", "breathing", "gasp", "sigh"],
        .speech: [
            "speech", "shout", "yell", "battle_cry", "children_shouting", "screaming", "whispering",
            "laughter", "baby_laughter", "giggling", "snicker", "belly_laugh", "chuckle_chortle",
            "crying_sobbing", "baby_crying", "chatter", "crowd", "babble", "cheering", "applause", "booing",
            // Other sounds people make: coughs and sneezes are common at night.
            "cough", "sneeze", "nose_blowing", "hiccup", "burp", "gargling", "slurp", "chewing", "biting",
            "clapping", "finger_snapping",
        ],
        .traffic: [
            "car_horn", "power_windows", "vehicle_skidding", "car_passing_by", "race_car", "truck", "air_horn",
            "reverse_beeps", "bus", "emergency_vehicle", "police_siren", "ambulance_siren", "fire_engine_siren",
            "siren", "motorcycle", "traffic_noise", "rail_transport", "train", "train_whistle", "train_horn",
            "railroad_car", "train_wheels_squealing", "subway_metro", "engine", "engine_knocking",
            "engine_starting", "engine_idling", "engine_accelerating_revving", "bicycle", "skateboard",
            "boat_water_vehicle", "motorboat_speedboat", "lawn_mower",
        ],
        .aircraft: ["aircraft", "helicopter", "airplane"],
        .animals: [
            "dog", "dog_bark", "dog_howl", "dog_bow_wow", "dog_growl", "dog_whimper", "cat", "cat_purr", "cat_meow",
            "horse_clip_clop", "horse_neigh", "cow_moo", "pig_oink", "sheep_bleat", "fowl", "chicken",
            "chicken_cluck", "rooster_crow", "turkey_gobble", "duck_quack", "goose_honk", "lion_roar", "bird",
            "bird_vocalization", "bird_chirp_tweet", "bird_squawk", "pigeon_dove_coo", "crow_caw", "owl_hoot",
            "bird_flapping", "insect", "cricket_chirp", "mosquito_buzz", "fly_buzz", "bee_buzz", "frog",
            "frog_croak", "snake_hiss", "snake_rattle", "whale_vocalization", "coyote_howl", "elk_bugle",
        ],
        .household: [
            "door", "door_sliding", "door_slam", "knock", "tap", "squeak", "drawer_open_close",
            "dishes_pots_pans", "cutlery_silverware", "chopping_food", "frying_food", "microwave_oven", "blender",
            "water_tap_faucet", "sink_filling_washing", "bathtub_filling_washing", "toilet_flush", "water_pump",
            "boiling", "liquid_dripping", "liquid_pouring", "liquid_trickle_dribble", "liquid_filling_container",
            "liquid_splashing", "hair_dryer", "toothbrush", "vacuum_cleaner", "electric_shaver", "sewing_machine",
            "mechanical_fan", "air_conditioner", "printer", "clock", "tick", "tick_tock", "keys_jangling",
            "coin_dropping", "zipper", "glass_clink", "glass_breaking", "person_walking", "person_shuffling",
            "person_running", "thump_thud", "hammer", "saw", "power_tool", "drill",
            // Generic water: in a bedroom this is nearly always plumbing (see vagueLabels for rain).
            "water", "gurgling", "stream_burbling", "liquid_sloshing", "liquid_squishing", "liquid_spraying",
            "underwater_bubbling",
            "fire", "fire_crackle", "typing", "typewriter", "typing_computer_keyboard", "writing", "scissors",
            "camera", "click", "crumpling_crinkling", "tearing", "crushing", "slap_smack", "whoosh_swoosh_swish",
            "bell", "chime",
        ],
        .weather: [
            "wind", "wind_rustling_leaves", "wind_noise_microphone", "thunderstorm", "thunder", "rain", "raindrop",
            "wind_chime", "waterfall", "ocean", "sea_waves",
        ],
        .musicTV: [
            "music", "singing", "choir_singing", "yodeling", "rapping", "humming", "whistling",
            "plucked_string_instrument", "guitar", "electric_guitar", "bass_guitar", "acoustic_guitar",
            "steel_guitar_slide_guitar", "guitar_tapping", "guitar_strum", "banjo", "sitar", "mandolin", "zither",
            "ukulele", "keyboard_musical", "piano", "electric_piano", "organ", "electronic_organ", "hammond_organ",
            "synthesizer", "harpsichord", "percussion", "drum_kit", "drum", "snare_drum", "bass_drum", "timpani",
            "tabla", "cymbal", "hi_hat", "tambourine", "rattle_instrument", "gong", "mallet_percussion",
            "marimba_xylophone", "glockenspiel", "vibraphone", "steelpan", "orchestra", "brass_instrument",
            "french_horn", "trumpet", "trombone", "bowed_string_instrument", "violin_fiddle", "cello",
            "double_bass", "wind_instrument", "flute", "saxophone", "clarinet", "oboe", "bassoon", "harp",
            "harmonica", "accordion", "bagpipes", "didgeridoo", "theremin", "disc_scratching",
        ],
        .alarmPhone: [
            "alarm_clock", "smoke_detector", "civil_defense_siren", "telephone", "telephone_bell_ringing",
            "ringtone", "door_bell", "beep",
        ],
    ]
}
