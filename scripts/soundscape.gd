class_name Soundscape
extends Node
## A self-contained, softly voiced instrument for the garden. All sounds are
## synthesized once into PCM buffers; playback needs no imported audio assets.
## Sparse felt notes and slow, quiet swells leave room for movement sounds.
## Notes wrap around a long loop with smooth envelopes at their own boundaries.

const SAMPLE_RATE: int = 22050
const AMBIENT_SECONDS: float = 32.0
const AMBIENT_VOLUME_DB: float = -24.0
const FOLD_VOLUME_DB: float = -20.0
const FOLD_COOLDOWN_SECONDS: float = 0.8
const VOICE_COUNT: int = 8
const SEED_NOTES: Array[float] = [523.251, 659.255, 783.991, 1046.502]

var muted: bool = false
var _ambience: AudioStreamPlayer
var _fold_voice: AudioStreamPlayer
var _fold_cooldown: float = 0.0
var _voices: Array[AudioStreamPlayer] = []
var _sounds: Dictionary = {}
var _seed_sounds: Array[AudioStreamWAV] = []
var _voice_cursor: int = 0
var _playback_enabled: bool = true


func _ready() -> void:
	# Automated headless runs have no listener or real audio device.
	_playback_enabled = DisplayServer.get_name() != "headless"
	_sounds[&"fold"] = _make_fold()
	_sounds[&"jump"] = _make_effect(&"jump", 0.17)
	_sounds[&"complete"] = _make_effect(&"complete", 2.4)
	_sounds[&"reset"] = _make_effect(&"reset", 0.65)
	for note_index in range(SEED_NOTES.size()):
		_seed_sounds.append(_make_effect(&"seed", 1.45, note_index))

	for voice_index in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.name = "GardenVoice%d" % voice_index
		voice.volume_db = -12.0
		add_child(voice)
		_voices.append(voice)

	_fold_voice = AudioStreamPlayer.new()
	_fold_voice.name = "FoldAir"
	_fold_voice.volume_db = FOLD_VOLUME_DB
	add_child(_fold_voice)

	_ambience = AudioStreamPlayer.new()
	_ambience.name = "QuietDimension"
	_ambience.stream = _make_ambient()
	_ambience.volume_db = -60.0
	add_child(_ambience)
	if _playback_enabled:
		_ambience.play()
	_ambience.stream_paused = muted


func _process(delta: float) -> void:
	_fold_cooldown = maxf(0.0, _fold_cooldown - delta)
	if is_instance_valid(_ambience) and not muted:
		_ambience.volume_db = move_toward(_ambience.volume_db, AMBIENT_VOLUME_DB, delta * 16.0)


func _exit_tree() -> void:
	stop_all()


func stop_all() -> void:
	# Release active playback before engine shutdown, including paused ambience.
	# Otherwise a looping WAV can remain held by its audio playback instance.
	if is_instance_valid(_ambience):
		_ambience.stream_paused = false
		_ambience.stop()
		_ambience.stream = null
	if is_instance_valid(_fold_voice):
		_fold_voice.stop()
		_fold_voice.stream = null
	_fold_cooldown = 0.0
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	_sounds.clear()
	_seed_sounds.clear()


## Mutes this instrument only, without changing the project's audio buses.
## This may also be called before the node enters the scene tree.
func set_muted(value: bool) -> void:
	muted = value
	if is_instance_valid(_ambience):
		if not muted and _ambience.stream_paused:
			_ambience.volume_db = -60.0
		_ambience.stream_paused = muted
	if muted:
		if is_instance_valid(_fold_voice):
			_fold_voice.stop()
		for voice in _voices:
			voice.stop()


func play_fold() -> void:
	if not _playback_enabled or muted or not is_instance_valid(_fold_voice):
		return
	if _fold_cooldown > 0.0 or _fold_voice.playing or not _sounds.has(&"fold"):
		return
	# A separate voice and cooldown keep Q/E taps from stacking or chopping
	# off a previous cue. Holding a fold never creates a continuous drone.
	_fold_voice.stream = _sounds[&"fold"]
	_fold_voice.play()
	_fold_cooldown = FOLD_COOLDOWN_SECONDS


func play_seed(index: int = 0) -> void:
	if not _seed_sounds.is_empty():
		_play_sound(_seed_sounds[posmod(index, _seed_sounds.size())])


func play_jump() -> void:
	_play_sound(_sounds.get(&"jump"))


func play_complete() -> void:
	_play_sound(_sounds.get(&"complete"))


func play_reset() -> void:
	_play_sound(_sounds.get(&"reset"))


func _play_sound(stream: AudioStreamWAV) -> void:
	if not _playback_enabled or muted or stream == null or _voices.is_empty():
		return
	# Idle voices let collected notes and other effects ring out together. Repeated
	# requests use a bounded pool so frantic input cannot accumulate players.
	var chosen: AudioStreamPlayer = _voices[_voice_cursor]
	for voice in _voices:
		if not voice.playing:
			chosen = voice
			break
	chosen.stream = stream
	chosen.play()
	_voice_cursor = (_voice_cursor + 1) % _voices.size()


func _make_ambient() -> AudioStreamWAV:
	var frame_count: int = int(SAMPLE_RATE * AMBIENT_SECONDS)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frame_count)
	right.resize(frame_count)
	# Open fifths move slowly through C, A, F, and G. These swells sit
	# well below the notes; there is no bright sustained chord or beat.
	var roots: Array[float] = [130.813, 110.0, 174.614, 97.999]
	for chord in range(roots.size()):
		_add_ambient_note(left, right, chord * 8.0, 12.0, roots[chord], 0.038, -0.24, true)
		_add_ambient_note(left, right, chord * 8.0 + 0.4, 11.6, roots[chord] * 1.5, 0.026, 0.24, true)
	# A handful of rounded, felt-like notes with generous space between them.
	var notes: Array[float] = [261.626, 329.628, 293.665, 220.0, 261.626, 196.0, 246.942, 293.665]
	var onsets: Array[float] = [1.4, 5.6, 9.5, 13.6, 17.4, 21.4, 25.8, 29.4]
	for index in range(notes.size()):
		var pan := -0.18 if index % 2 == 0 else 0.18
		_add_ambient_note(left, right, onsets[index], 4.8, notes[index], 0.38, pan, false)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 4)
	for frame in range(frame_count):
		_write_frame(pcm, frame, left[frame], right[frame])
	var stream: AudioStreamWAV = _stream_from_pcm(pcm)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	return stream


func _add_ambient_note(left: PackedFloat32Array, right: PackedFloat32Array,
		onset: float, duration: float, frequency: float, volume: float, pan: float, pad: bool) -> void:
	var start_frame := int(onset * SAMPLE_RATE)
	var frame_count := int(duration * SAMPLE_RATE)
	var gain_left := volume * sqrt((1.0 - pan) * 0.5)
	var gain_right := volume * sqrt((1.0 + pan) * 0.5)
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var progress := float(frame) / frame_count
		var phase := TAU * frequency * time
		var value: float
		if pad:
			value = sin(phase) * pow(sin(PI * progress), 2.0)
		else:
			var attack := smoothstep(0.0, 0.075, time)
			var release := pow(1.0 - progress, 2.0)
			value = (0.80 * sin(phase) * exp(-0.8 * time)
				+ 0.12 * sin(phase * 2.0) * exp(-2.4 * time)
				+ 0.025 * sin(phase * 3.0) * exp(-4.0 * time)) * attack * release
		# Circular mixing lets tails cross the seam naturally without requiring
		# detuned pitches, truncated notes, or a repeated fade to silence.
		var target := (start_frame + frame) % left.size()
		left[target] += value * gain_left
		right[target] += value * gain_right


func _make_fold() -> AudioStreamWAV:
	var frame_count := int(SAMPLE_RATE * 0.48)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 4)
	var random := RandomNumberGenerator.new()
	random.seed = 0xF01D
	var low := 0.0
	var soft := 0.0
	var rumble := 0.0
	for frame in range(frame_count):
		# Two gentle low-pass stages remove hiss; subtracting the very low
		# component removes rumble. The result is air, without a rising pitch.
		low += 0.13 * (random.randf_range(-1.0, 1.0) - low)
		soft += 0.13 * (low - soft)
		rumble += 0.015 * (soft - rumble)
		var progress := float(frame) / (frame_count - 1)
		var envelope := pow(sin(PI * progress), 2.0)
		var value := (soft - rumble) * envelope * 0.65
		_write_frame(pcm, frame, value, value)
	return _stream_from_pcm(pcm)


func _make_effect(kind: StringName, duration: float, variant: int = 0) -> AudioStreamWAV:
	var frame_count: int = int(SAMPLE_RATE * duration)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 4)
	for frame in range(frame_count):
		var time: float = float(frame) / SAMPLE_RATE
		var progress: float = time / duration
		var sample_value: float = 0.0
		var pan: float = 0.0
		match kind:
			&"jump":
				var phase: float = TAU * (320.0 * time + 550.0 * time * time)
				sample_value = 0.32 * sin(phase) * pow(sin(PI * progress), 2.0)
			&"seed":
				sample_value = _bell(time, SEED_NOTES[variant], duration) * 0.75
				pan = -0.3 + float(variant) * 0.2
			&"complete":
				for note in range(SEED_NOTES.size()):
					var onset: float = float(note) * 0.16
					sample_value += _bell(time - onset, SEED_NOTES[note], duration - onset) * 0.30
				pan = sin(progress * TAU) * 0.18
			&"reset":
				sample_value = _bell(time, 261.625, duration) * 0.40
				sample_value += _bell(time - 0.14, 196.0, duration - 0.14) * 0.28
		# Keep collection notes gently spread without exaggerated stereo motion.
		var left: float = sample_value * sqrt((1.0 - pan) * 0.5)
		var right: float = sample_value * sqrt((1.0 + pan) * 0.5)
		_write_frame(pcm, frame, left, right)
	return _stream_from_pcm(pcm)


## Short attack plus damped partials suggest a bell without a hard transient.
## The final taper reaches zero so finite PCM effects do not end with a click.
func _bell(time: float, frequency: float, duration: float) -> float:
	if time <= 0.0 or time >= duration:
		return 0.0
	var attack: float = minf(time / 0.012, 1.0)
	attack = attack * attack * (3.0 - 2.0 * attack)
	var release: float = pow(1.0 - time / duration, 1.5)
	var phase: float = TAU * frequency * time
	var fundamental: float = 0.65 * sin(phase) * exp(-2.2 * time)
	var overtone: float = 0.23 * sin(phase * 2.002) * exp(-4.6 * time)
	var shimmer: float = 0.09 * sin(phase * 3.997) * exp(-7.5 * time)
	return (fundamental + overtone + shimmer) * attack * release


func _stream_from_pcm(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = pcm
	return stream


func _write_frame(pcm: PackedByteArray, frame: int, left: float, right: float) -> void:
	pcm.encode_s16(frame * 4, int(clampf(left, -1.0, 1.0) * 32767.0))
	pcm.encode_s16(frame * 4 + 2, int(clampf(right, -1.0, 1.0) * 32767.0))
