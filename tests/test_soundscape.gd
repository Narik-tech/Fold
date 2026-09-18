extends SceneTree
## Audio regressions: PCM headroom, a seamless loop, bounded fold playback,
## and mute/cleanup. The dummy audio driver makes this safe to run headless.
## godot --headless --path . --script tests/test_soundscape.gd

const Instrument = preload("res://scripts/soundscape.gd")
var sound: Node
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	sound = Instrument.new()
	sound.set_muted(true)
	root.add_child(sound)
	sound.set_process(false)
	_expect(sound.muted and not sound._ambience.playing, "Mute set before entering the tree is preserved")
	_test_streams()
	_test_fold_playback()
	_test_mute_and_cleanup()
	# Let the dummy audio mixer release the stopped playback instances.
	await create_timer(0.2).timeout
	sound.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: all %d soundscape checks passed." % checks)
	else:
		printerr("FAIL: %d of %d soundscape checks failed." % [failures, checks])
	quit(1 if failures else 0)


func _test_streams() -> void:
	var ambient: AudioStreamWAV = sound._ambience.stream
	var fold: AudioStreamWAV = sound._sounds[&"fold"]
	var ambient_stats: Dictionary = _check_pcm(ambient, "Ambient music")
	var fold_stats: Dictionary = _check_pcm(fold, "Fold cue")
	var ambient_frames: int = ambient.data.size() / 4
	_expect(ambient.loop_mode == AudioStreamWAV.LOOP_FORWARD and ambient.loop_begin == 0 and ambient.loop_end == ambient_frames, "Music loops over its complete PCM buffer")
	_expect(ambient.get_length() >= 24.0, "Music gives phrases room before repeating")
	_expect(fold.loop_mode == AudioStreamWAV.LOOP_DISABLED and fold.get_length() <= 0.65, "Fold cue is short and never loops")
	var seam_step: float = 0.0
	var nearby_step: float = 0.0
	for channel in range(2):
		seam_step = maxf(seam_step, absf(_sample(ambient.data, 0, channel) - _sample(ambient.data, ambient_frames - 1, channel)))
		for frame in range(1, 128):
			nearby_step = maxf(nearby_step, absf(_sample(ambient.data, frame, channel) - _sample(ambient.data, frame - 1, channel)))
			nearby_step = maxf(nearby_step, absf(_sample(ambient.data, ambient_frames - frame, channel) - _sample(ambient.data, ambient_frames - frame - 1, channel)))
	_expect(seam_step < 0.025 and seam_step <= nearby_step * 1.5 + 2.0 / 32767.0, "The music loop seam has no abrupt waveform jump")
	var fold_frames: int = fold.data.size() / 4
	for channel in range(2):
		_expect(absf(_sample(fold.data, 0, channel)) <= 1.0 / 32767.0 and absf(_sample(fold.data, fold_frames - 1, channel)) <= 1.0 / 32767.0, "Fold cue fades to silence at both boundaries, channel %d" % channel)
	var ambient_gain: float = db_to_linear(Instrument.AMBIENT_VOLUME_DB)
	var fold_gain: float = db_to_linear(Instrument.FOLD_VOLUME_DB)
	_expect(ambient_stats.peak * ambient_gain < 0.06 and ambient_stats.rms * ambient_gain < 0.02, "Music has conservative peak and average playback levels")
	_expect(fold_stats.peak * fold_gain < 0.06 and fold_stats.rms * fold_gain < 0.02, "Fold feedback stays quietly below full scale")
	print("Audio levels: music %.1f dBFS peak / %.1f dBFS RMS; fold %.1f dBFS peak / %.1f dBFS RMS; loop step %.6f." % [linear_to_db(ambient_stats.peak * ambient_gain), linear_to_db(ambient_stats.rms * ambient_gain), linear_to_db(fold_stats.peak * fold_gain), linear_to_db(fold_stats.rms * fold_gain), seam_step])


func _test_fold_playback() -> void:
	sound.set_muted(false)
	sound._playback_enabled = false
	sound.play_fold()
	_expect(not sound._fold_voice.playing and is_zero_approx(sound._fold_cooldown), "Disabled playback does not consume the first fold cue")
	sound._playback_enabled = true
	# Headless setup skips ambience playback; start it on the dummy driver so
	# the mute assertions below exercise a running stream.
	sound._ambience.play()
	sound.play_fold()
	_expect(sound._fold_voice.playing and sound._fold_cooldown > 0.0, "The first fold starts immediately")
	var cooldown: float = sound._fold_cooldown
	for request in range(100):
		sound.play_fold()
	_expect(is_equal_approx(sound._fold_cooldown, cooldown), "Rapid input does not restart the cue or extend its cooldown")
	var playing_voices: int = 0
	for voice in sound._voices:
		if voice.playing:
			playing_voices += 1
	_expect(playing_voices == 0, "Fold spam never fills the shared effect voices")
	sound._process(Instrument.FOLD_COOLDOWN_SECONDS + 0.01)
	sound.play_fold()
	_expect(is_zero_approx(sound._fold_cooldown), "An active fold cue is not cut off even after its cooldown")
	sound._fold_voice.stop()
	sound.play_fold()
	_expect(sound._fold_voice.playing and sound._fold_cooldown > 0.0, "A later fold can play once the cue and cooldown finish")


func _test_mute_and_cleanup() -> void:
	sound.play_jump()
	sound.play_seed()
	sound.set_muted(true)
	_expect(sound._ambience.stream_paused and not sound._fold_voice.playing, "Mute pauses music and stops the dedicated fold voice")
	for voice in sound._voices:
		_expect(not voice.playing, "Mute stops shared effect voice %s" % voice.name)
	sound._process(Instrument.FOLD_COOLDOWN_SECONDS + 0.01)
	sound.play_fold()
	sound.play_jump()
	_expect(not sound._fold_voice.playing and is_zero_approx(sound._fold_cooldown), "Muted fold requests do not consume a future cue")
	sound.set_muted(false)
	_expect(not sound._ambience.stream_paused, "Unmuting resumes the music state")
	sound.play_fold()
	_expect(sound._fold_voice.playing, "Fold feedback remains available after unmuting")
	sound.stop_all()
	_expect(sound._ambience.stream == null and sound._fold_voice.stream == null, "Cleanup releases music and dedicated fold streams")
	for voice in sound._voices:
		_expect(not voice.playing and voice.stream == null, "Cleanup releases shared effect voice %s" % voice.name)
	sound.stop_all()
	sound.play_fold()
	sound.play_jump()
	_expect(not sound._fold_voice.playing, "Repeated cleanup and later cue requests remain safe")


func _check_pcm(stream: AudioStreamWAV, label: String) -> Dictionary:
	_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.stereo and stream.mix_rate > 0 and stream.data.size() > 0 and stream.data.size() % 4 == 0, "%s is valid stereo PCM" % label)
	var pcm: PackedByteArray = stream.data
	var peak: float = 0.0
	var energy: float = 0.0
	var total: float = 0.0
	var count: int = pcm.size() / 2
	for index in range(count):
		var value: float = float(pcm.decode_s16(index * 2)) / 32767.0
		peak = maxf(peak, absf(value))
		energy += value * value
		total += value
	var rms: float = sqrt(energy / count)
	_expect(peak > 0.002 and peak < 0.95 and rms > 0.0001, "%s is audible with ample unclipped headroom" % label)
	_expect(absf(total / count) < 0.005, "%s has negligible DC offset" % label)
	return {"peak": peak, "rms": rms}


func _sample(pcm: PackedByteArray, frame: int, channel: int) -> float:
	return float(pcm.decode_s16(frame * 4 + channel * 2)) / 32767.0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
