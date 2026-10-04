class_name GameAudio
extends Node

var muted := false
var rain_player: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var sounds := {}
var voice_index := 0
const RATE := 22050

func _ready() -> void:
	for n in 4:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -15.0
		add_child(voice)
		voices.append(voice)
	rain_player = AudioStreamPlayer.new()
	add_child(rain_player)
	sounds["confirm"] = _tone(660.0, 0.12)
	sounds["earth"] = _tone(90.0, 0.28, true)
	sounds["phase"] = _tone(220.0, 0.8)
	sounds["arrival"] = _tone(880.0, 0.6)
	sounds["loss"] = _tone(110.0, 1.0)
	sounds["error"] = _tone(150.0, 0.14)
	rain_player.stream = _rain_stream()

func play_cue(kind: String) -> void:
	if muted or not sounds.has(kind):
		return
	var voice := voices[voice_index % voices.size()]
	voice_index += 1
	voice.stream = sounds[kind]
	voice.play()

func set_rain(active: bool, heavy: bool) -> void:
	rain_player.volume_db = -17.0 if heavy else -25.0
	if active and not muted:
		if not rain_player.playing:
			rain_player.play()
	else:
		rain_player.stop()

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		rain_player.stop()
		for voice in voices:
			voice.stop()

func _tone(frequency: float, duration: float, noise: bool = false) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var count := roundi(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for n in count:
		var t := float(n) / RATE
		var attack := minf(1.0, t / 0.012)
		var envelope := attack * exp(-t * 5.0 / duration)
		var sample := (sin(TAU * frequency * t) * 0.6 + sin(TAU * frequency * 2.01 * t) * 0.25) * envelope
		if noise:
			sample = (sample * 0.3 + rng.randf_range(-0.7, 0.7)) * envelope
		bytes.encode_s16(n * 2, roundi(sample * 22000.0))
	return _wav(bytes)

func _rain_stream() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8103
	var count := RATE * 2
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var low := 0.0
	for n in count:
		var sample := rng.randf_range(-1.0, 1.0)
		low = low * 0.83 + sample * 0.17
		var amplitude := 0.8 + 0.2 * sin(TAU * n / count * 3.0)
		bytes.encode_s16(n * 2, roundi((sample * 0.45 + low * 1.5) * 20000.0 * amplitude))
	var stream := _wav(bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream

func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
