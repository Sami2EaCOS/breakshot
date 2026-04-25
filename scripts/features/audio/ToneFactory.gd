class_name ToneFactory
extends RefCounted

static func make_tone(start_hz: float, end_hz: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var sample_count := int(duration * float(sample_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	for i in range(sample_count):
		var t := float(i) / maxf(1.0, float(sample_count - 1))
		var hz := lerpf(start_hz, end_hz, t)
		phase += TAU * hz / float(sample_rate)
		var envelope := pow(1.0 - t, 1.8)
		var sample := sin(phase) * envelope * volume
		if start_hz < 250.0:
			sample += sin(phase * 0.47) * envelope * volume * 0.55
		var pcm := int(clampf(sample, -1.0, 1.0) * 32767.0)
		if pcm < 0:
			pcm += 65536
		bytes[i * 2] = pcm & 0xff
		bytes[i * 2 + 1] = (pcm >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream
