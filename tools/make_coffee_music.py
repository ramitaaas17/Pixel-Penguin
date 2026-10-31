"""Original, gently articulated chiptune loop for Café del Deshielo (no samples)."""
import math
from pathlib import Path
import struct
import wave

rate = 22050
beat = 60 / 104
length = beat * 32
notes = [76, 79, 81, 79, 76, 74, 72, 74, 76, 79, 84, 81, 79, 76, 74, 72,
         74, 77, 81, 79, 77, 74, 72, 71, 72, 76, 79, 76, 74, 72, 71, 72]
roots = [48, 48, 45, 45, 53, 53, 55, 55]
def hz(note):
    return 440 * 2 ** ((note - 69) / 12)
def voice(freq, t, duration, pulse=False):
    envelope = min(1, t / .012) * min(1, max(0, duration - t) / .055)
    phase = (freq * t) % 1
    tone = (1 if phase < .25 else -1 / 3) if pulse else 4 * abs(phase - .5) - 1
    return tone * envelope
samples = []
for index in range(round(rate * length)):
    t = index / rate
    tick = min(31, int(t / beat))
    local = t - tick * beat
    melody = .25 * voice(hz(notes[tick]), local, beat * .8, True)
    half = int(t / (beat / 2))
    bass_t = t - half * beat / 2
    root = roots[min(7, tick // 4)]
    bass_note = root if half % 2 == 0 else root + 7
    bass = .18 * voice(hz(bass_note), bass_t, beat * .42)
    arpeggio = .09 * voice(hz(root + [12, 16, 19, 16][half % 4]), bass_t, beat * .36)
    value = max(-1, min(1, melody + bass + arpeggio))
    samples.append(struct.pack('<h', int(value * 22000)))
path = Path(__file__).resolve().parents[1] / 'assets/audio/coffee_loop.wav'
with wave.open(str(path), 'wb') as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(rate)
    audio.writeframes(b''.join(samples))
print('Original coffee loop:', path.name, '32 beats, mono 22050 Hz')
