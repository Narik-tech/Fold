class_name Soundscape
extends Node
## A self-contained, softly voiced instrument for the garden. All sounds are
## synthesized once into PCM buffers; playback needs no imported audio assets.
## The eight-second ambient loop uses whole cycles for its notes and modulation,
## so its waveform remains continuous across the loop boundary.

const SAMPLE_RATE: int = 22050
const AMBIENT_SECONDS: float = 8.0
const VOICE_COUNT: int = 8
const SEED_NOTES: Array[float] = [523.251, 659.255, 783.991, 1046.502]

var muted: bool = false
var _ambience: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _sounds: Dictionary = {}
var _seed_sounds: Array[AudioStreamWAV] = []
var _voice_cursor: int = 0
var _playback_enabled: bool = true


func _ready() -> void:
	# Automated headless runs have no listener or real audio device.
	_playback_enabled = DisplayServer.get_name() != "headless"
	_sounds[&"fold"] = _make_effect(&"fold", 0.82)
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

	_ambience = AudioStreamPlayer.new()
	_ambience.name = "QuietDimension"
	_ambience.stream = _make_ambient()
	_ambience.volume_db = -22.0
	add_child(_ambience)
	if _playback_enabled:
		_ambience.play()
	_ambience.stream_paused = muted


func _exit_tree() -> void:
	stop_all()


func stop_all() -> void:
	# Release active playback before engine shutdown, including paused ambience.
	# Otherwise a looping WAV can remain held by its audio playback instance.
	if is_instance_valid(_ambience):
		_ambience.stream_paused = false
		_ambience.stop()
		_ambience.stream = null
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
		_ambience.stream_paused = muted
	if muted:
		for voice in _voices:
			voice.stop()


func play_fold() -> void:
	_play_sound(_sounds.get(&"fold"))


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
	# Idle voices let collected notes and folds ring out together. Repeated
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
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 4)
	# Each frequency completes an integer number of cycles in eight seconds.
	# The slight tuning offsets are below a cent at the upper voices.
	var frequencies: Array[float] = [130.875, 164.875, 196.0, 261.625]
	for frame in range(frame_count):
		var time: float = float(frame) / SAMPLE_RATE
		var slow_phase: float = TAU * time / AMBIENT_SECONDS
		var left: float = 0.0
		var right: float = 0.0
		for note in range(frequencies.size()):
			var note_phase: float = TAU * frequencies[note] * time
			var swell: float = 0.75 + 0.20 * sin(slow_phase + note * 1.7)
			var amplitude: float = 0.17 * swell
			left += amplitude * (sin(note_phase + note * 0.42) + 0.12 * sin(note_phase * 2.0))
			right += amplitude * (sin(note_phase + note * 0.42 + 0.13) + 0.12 * sin(note_phase * 2.0 + 0.2))
		_write_frame(pcm, frame, left, right)
	var stream: AudioStreamWAV = _stream_from_pcm(pcm)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	return stream


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
			&"fold":
				# An integrated chirp bends upward while moving across the stereo
				# field. A full sine envelope gives silence at both boundaries.
				var phase: float = TAU * (196.0 * time + 95.0 * time * time)
				var envelope: float = pow(sin(PI * progress), 2.0)
				sample_value = envelope * (0.34 * sin(phase) + 0.15 * sin(phase * 1.5) + 0.08 * sin(phase * 2.0))
				pan = sin((progress - 0.5) * PI) * 0.55
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
		# Equal-power panning preserves volume as the fold moves sideways.
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
