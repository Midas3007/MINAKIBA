"""MINAKIBA opening film: original score, rendered in code.

Koto (Karplus-Strong) in the Japanese In scale (A, Bb, D, E, F), warm fingered bass, hand congas,
shekere, a soft kick and warm pads. No log drums. 100 BPM, 48 s, synced to opening.html.

    python3 score.py out/score.wav
"""
import sys
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
DUR = 48.0
BPM = 100
BEAT = 60 / BPM                     # 0.6 s
BAR = 4 * BEAT                      # 2.4 s
rng = np.random.default_rng(7)      # fixed seed: the score renders the same every time

N = int(SR * DUR)
NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'Bb': 10, 'B': 11}


def hz(name):
    """'A4' -> 440.0, 'Bb3' -> 233.08"""
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[pitch] + 12 * (octave + 1) - 69) / 12)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], 'bandpass', fs=SR, output='sos'), x)


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, 'lowpass', fs=SR, output='sos'), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, 'highpass', fs=SR, output='sos'), x)


# ---------- tracks: each is mono, placed with a pan and a reverb send ----------
class Track:
    def __init__(self, pan=0.0, send=0.25, gain=1.0):
        self.x = np.zeros(N + SR * 4)
        self.pan, self.send, self.gain = pan, send, gain

    def add(self, t, sig):
        i = int(round(t * SR))
        self.x[i:i + len(sig)] += sig[: max(0, len(self.x) - i)]


koto = Track(pan=0.28, send=0.38, gain=1.15)
bass = Track(pan=0.0, send=0.08, gain=0.5)
conga_hi = Track(pan=-0.38, send=0.2, gain=0.42)
conga_lo = Track(pan=0.34, send=0.2, gain=0.46)
shekere = Track(pan=-0.12, send=0.22, gain=0.13)
kick = Track(pan=0.0, send=0.06, gain=0.45)
pad = Track(pan=0.0, send=0.5, gain=0.42)
hit = Track(pan=0.0, send=0.35, gain=0.42)


# ---------- instruments ----------
def koto_note(f, dur=2.4, vel=1.0, bright=0.6):
    """Karplus-Strong pluck: bright attack, a little pitch bend down into the note."""
    n_period = int(SR / f)                      # integer delay; tuned exactly by the resample below
    f_ks = SR / n_period
    length = int(SR * dur) + n_period * 4
    y = np.zeros(length)
    exc = rng.uniform(-1, 1, n_period)
    exc = exc - np.roll(exc, int(n_period * 0.18))     # pluck near the bridge
    exc = lowpass(exc, 2500 + 6000 * bright, 1)
    y[:n_period] = exc
    t60 = np.interp(f, [110, 1000], [3.4, 1.4])
    g = 10 ** (-3 / (t60 * f_ks))
    a = 0.5 + 0.12 * bright                     # loss filter (higher = brighter sustain)
    k = 1
    while (k + 1) * n_period <= length:
        prev = y[(k - 1) * n_period:k * n_period]
        prev2 = np.concatenate(([y[(k - 1) * n_period - 1] if k > 1 else 0.0], prev[:-1]))
        y[k * n_period:(k + 1) * n_period] = g * (a * prev + (1 - a) * prev2)
        k += 1
    # tune to f and add the attack bend (starts ~35 cents sharp, settles in ~40 ms)
    m = int(SR * dur)
    tt = np.arange(m) / SR
    ratio = (f / f_ks) * 2 ** (35 * np.exp(-tt / 0.02) / 1200)
    pos = np.concatenate(([0.0], np.cumsum(ratio)[:-1]))
    out = np.interp(pos, np.arange(length), y)
    click = highpass(rng.uniform(-1, 1, int(SR * 0.006)), 3000) * np.linspace(1, 0, int(SR * 0.006)) * 0.25
    out[:len(click)] += click
    out *= np.minimum(1, (m - np.arange(m)) / (SR * 0.08))    # gentle tail fade
    return 0.6 * vel * out / (np.max(np.abs(out)) + 1e-9)


def bass_note(f, dur, vel=1.0):
    """Warm fingered bass: a few harmonics, soft finger attack, quick decay into a round sustain."""
    m = int(SR * (dur + 0.25))
    tt = np.arange(m) / SR
    s = np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(4 * np.pi * f * tt) + 0.12 * np.sin(6 * np.pi * f * tt)
    env = np.minimum(1, tt / 0.006) * (0.55 + 0.45 * np.exp(-tt / 0.18))
    env *= np.clip((dur + 0.25 - tt) / 0.25, 0, 1)
    thump = np.sin(2 * np.pi * 2 * f * tt) * np.exp(-tt / 0.02) * 0.3
    return vel * lowpass(s * env + thump, 900) * 0.8


def conga(kind, f, vel=1.0):
    """Hand conga: open tone, slap or mute."""
    if kind == 'open':
        dur, tau, noise, tone = 0.5, 0.17, 0.10, 1.0
    elif kind == 'slap':
        dur, tau, noise, tone = 0.25, 0.045, 0.75, 0.6
    else:  # mute
        dur, tau, noise, tone = 0.12, 0.03, 0.18, 0.7
    m = int(SR * dur)
    tt = np.arange(m) / SR
    ff = f * (1 + 0.25 * np.exp(-tt / 0.012))
    body = np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-tt / tau) * tone
    skin = bandpass(rng.uniform(-1, 1, m), 900, 5000) * np.exp(-tt / (0.02 if kind != 'open' else 0.012)) * noise
    return vel * (body + skin) * np.minimum(1, tt / 0.0015)


def shaker(vel=1.0):
    m = int(SR * 0.09)
    tt = np.arange(m) / SR
    env = np.minimum(1, tt / 0.004) * np.exp(-tt / 0.028)
    return vel * bandpass(rng.uniform(-1, 1, m), 3500, 10000) * env


def kick_drum(vel=1.0):
    m = int(SR * 0.5)
    tt = np.arange(m) / SR
    f = 48 + 60 * np.exp(-tt / 0.035)
    return vel * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.26) * np.minimum(1, tt / 0.002)


def low_hit():
    """The soft low hit when the blue block appears: a deep boom with a short swell into it."""
    m = int(SR * 3.0)
    tt = np.arange(m) / SR
    f = 42 + 30 * np.exp(-tt / 0.06)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.9) * np.minimum(1, tt / 0.004)
    air = lowpass(rng.uniform(-1, 1, m), 400) * np.exp(-tt / 0.5) * 0.25
    pre = int(SR * 0.7)
    swell = lowpass(rng.uniform(-1, 1, pre), 700) * np.linspace(0, 1, pre) ** 3 * 0.18
    return np.concatenate((swell, boom + air)), 0.7


def pad_chord(names, dur, attack=1.5, release=1.6, vel=1.0):
    """Warm pad: detuned additive saws with a soft roll-off and slow breathing."""
    m = int(SR * (dur + release))
    tt = np.arange(m) / SR
    out = np.zeros(m)
    for name in names:
        f0 = hz(name)
        for det in (-0.004, 0.0, 0.0045):
            f = f0 * (1 + det)
            for h in range(1, 9):
                if f * h > 4000:
                    break
                out += np.sin(2 * np.pi * f * h * tt + rng.uniform(0, 6.28)) / h ** 1.6
    env = np.minimum(1, tt / attack) * np.clip((dur + release - tt) / release, 0, 1)
    env *= 1 + 0.08 * np.sin(2 * np.pi * 0.23 * tt)
    return vel * out * env / (len(names) * 3)


# ---------- the arrangement (times in beats; 1 beat = 0.6 s) ----------
def b(x):
    return x * BEAT


def pluck(beat, name, dur=2.4, vel=0.8, bright=0.6):
    koto.add(b(beat), koto_note(hz(name), dur, vel, bright))


# intro: koto motif alone, pad swell. The gold point pulses on beats 2-6 (= opening.html PULSES).
for beat, name, v in [(2, 'A4', 0.6), (3, 'E5', 0.65), (4, 'F5', 0.7), (5, 'E5', 0.6), (6, 'D5', 0.65)]:
    pluck(beat, name, 2.6, v)
pluck(7, 'A4', 3.0, 0.5)
pad.add(0.0, pad_chord(['A2', 'E3', 'A3'], 9.6, attack=4.0))
# the point stretches into the bars: an answering phrase
for beat, name, v in [(9, 'E5', 0.55), (10, 'F5', 0.6), (11, 'E5', 0.5), (13, 'D5', 0.55), (14, 'Bb4', 0.5), (15, 'A4', 0.55)]:
    pluck(beat, name, 2.6, v)
pad.add(b(16), pad_chord(['D3', 'A3', 'F4'], 8 * BEAT, attack=2.0))
# one koto pluck per fan blade (= opening.html BLADES, beats 17-21)
for beat, name in zip(range(17, 22), ['A4', 'D5', 'E5', 'F5', 'A5']):
    pluck(beat, name, 3.0, 0.85, 0.75)
# the blue block: soft low hit on beat 24, warm pads under the reveal
sig, pre = low_hit()
hit.add(b(24) - pre, sig)
pad.add(b(24), pad_chord(['F2', 'C3', 'A3', 'E4'], 6 * BEAT, attack=0.8))
for beat, name, v in [(26, 'A5', 0.55), (28, 'F5', 0.5), (29, 'E5', 0.5)]:
    pluck(beat, name, 2.6, v)

# the groove: congas and shekere enter on beat 30 with the wordmark, bass and kick on beat 32
GROOVE = [(30, 68), (72, 76)]          # drops out for bar 17 (beats 68-72) under "The fund is open."


def in_groove(beat):
    return any(a <= beat < z for a, z in GROOVE)


def human(sd=0.006):
    return rng.normal(0, sd)


CONGA = [  # (16th step in a 2-beat cell, drum, kind, velocity)
    (0, 'lo', 'mute', 0.5), (2, 'hi', 'mute', 0.35), (4, 'hi', 'slap', 0.85), (6, 'hi', 'mute', 0.35),
    (7, 'lo', 'open', 0.8),
]
for cell in range(30, 76, 2):
    for step, drum, kind, v in CONGA:
        beat = cell + step / 4
        if not in_groove(beat):
            continue
        f = 330 if drum == 'hi' else 220
        tr = conga_hi if drum == 'hi' else conga_lo
        tr.add(b(beat) + human(), conga(kind, f, v * rng.uniform(0.85, 1.05)))
    # every other cell the low drum answers with a second open tone
    if (cell // 2) % 2 == 1 and in_groove(cell + 1.75):
        conga_lo.add(b(cell + 1.75) + human(), conga('open', 196, 0.7))
for s16 in range(30 * 4, 76 * 4):
    beat = s16 / 4
    if in_groove(beat):
        accent = 1.0 if s16 % 2 == 1 else 0.55          # off-beat 8ths lead
        if s16 % 4 == 2:
            accent = 0.8
        shekere.add(b(beat) + human(0.004), shaker(accent * rng.uniform(0.8, 1.0)))
for beat in range(32, 76):
    if in_groove(beat) and beat % 2 == 0:
        kick.add(b(beat), kick_drum(0.7 if beat % 4 == 0 else 0.5))

# bass, bar by bar from bar 8 (beat 32): A minor / D minor colours
PROG = ['A', 'F', 'D', 'E', 'A', 'F', 'D', 'E', 'A']   # bars 8..16
FIFTH = {'A': 'E', 'F': 'A', 'D': 'A', 'E': 'E'}
for i, root in enumerate(PROG):
    bar0 = 32 + 4 * i
    r1 = hz(root + ('1' if root == 'A' else '2'))   # A1, D2, E2, F2
    r2, f5 = 2 * r1, hz(FIFTH[root] + '2')
    for beat, f, d, v in [(0, r1, 0.9, 0.95), (1.5, r2, 0.35, 0.6), (2, f5, 0.85, 0.8), (3, r1, 0.35, 0.65), (3.5, r2 if i % 2 else f5, 0.35, 0.55)]:
        bass.add(b(bar0 + beat) + human(0.004), bass_note(f, d * BEAT, v))
bass.add(b(72), bass_note(hz('D2'), 1.4 * BEAT, 0.9))
bass.add(b(73.5), bass_note(hz('D3'), 0.4 * BEAT, 0.55))
bass.add(b(74), bass_note(hz('F2'), 0.9 * BEAT, 0.8))
bass.add(b(75), bass_note(hz('E2'), 0.9 * BEAT, 0.75))
bass.add(b(76), bass_note(hz('A1') * 1.0, 3.6, 0.9))

# koto over the wordmark: one soft pluck per letter (eighths), then one per root
for i, name in enumerate(['A4', 'E5', 'A5', 'E5', 'F5', 'E5', 'D5', 'E5']):
    pluck(31 + 0.5 * i, name, 1.6, 0.42, 0.5)
for i, name in enumerate(['D5', 'E5', 'F5', 'A5']):
    pluck(35 + 0.5 * i, name, 1.8, 0.5, 0.6)
# markets: melody, with a high accent on each golden gap (= opening.html PEAKS, beats 44, 48, 52)
MEL = [(38, 'E5', 0.55), (38.5, 'F5', 0.5), (39, 'E5', 0.5), (40, 'D5', 0.55), (41, 'A4', 0.5), (42, 'Bb4', 0.45), (42.5, 'A4', 0.45),
       (45, 'F5', 0.5), (45.5, 'E5', 0.45), (46, 'D5', 0.5), (47, 'E5', 0.5),
       (49, 'A5', 0.5), (49.5, 'F5', 0.45), (50, 'E5', 0.5), (51, 'D5', 0.5),
       (53, 'A5', 0.5), (54, 'F5', 0.45), (54.5, 'E5', 0.45), (55, 'D5', 0.5)]
for beat, name, v in MEL:
    pluck(beat, name, 2.0, v)
for beat, (lo, hi) in zip([44, 48, 52], [('A5', 'A6'), ('D6', 'D5'), ('E6', 'A5')]):
    pluck(beat, lo, 2.8, 0.8, 0.85)
    pluck(beat + 0.02, hi, 2.4, 0.4, 0.85)
pad.add(b(38), pad_chord(['A2', 'E3', 'C4'], 18 * BEAT, attack=2.5, vel=0.6))
# cards: a pluck as each card closes (beats 59, 60, 61), then a quiet answer
for beat, name in [(59, 'D5'), (60, 'E5'), (61, 'A5')]:
    pluck(beat, name, 2.4, 0.65, 0.7)
for beat, name, v in [(62, 'F5', 0.45), (63, 'E5', 0.45), (64, 'D5', 0.45), (64.5, 'E5', 0.4), (65, 'A4', 0.45)]:
    pluck(beat, name, 2.0, v)
pad.add(b(56), pad_chord(['D3', 'A3', 'F4'], 12 * BEAT, attack=2.0, vel=0.7))
# the lift: a rising arpeggio, then a held koto chord and pad as the groove drops out for one bar
for i, name in enumerate(['A4', 'D5', 'E5', 'F5', 'A5', 'D6']):
    pluck(66 + 0.33 * i, name, 1.6, 0.45 + 0.06 * i, 0.7)
for i, name in enumerate(['A3', 'E4', 'A4', 'D5', 'E5']):
    koto.add(b(68) + 0.025 * i, koto_note(hz(name), 4.2, 0.75, 0.65))
pad.add(b(66), pad_chord(['A2', 'E3', 'A3', 'D4', 'E4'], 10 * BEAT, attack=1.2))
# groove returns, a last phrase
for beat, name, v in [(72, 'E5', 0.55), (73, 'F5', 0.55), (73.5, 'E5', 0.5), (74, 'D5', 0.55), (75, 'A4', 0.5)]:
    pluck(beat, name, 2.0, v)
# end chord rings and fades
for i, name in enumerate(['A3', 'E4', 'A4', 'E5', 'A5']):
    koto.add(b(76) + 0.03 * i, koto_note(hz(name), 2.4, 0.7, 0.6))
pad.add(b(76), pad_chord(['A2', 'E3', 'A3', 'E4'], 1.6, attack=0.6, release=1.2))
kick.add(b(76), kick_drum(0.5))


# ---------- mix ----------
def reverb_ir(seconds=2.4, pre=0.018):
    m = int(SR * seconds)
    tt = np.arange(m) / SR
    ir = np.zeros((m + int(SR * pre), 2))
    for ch in range(2):
        noise = rng.uniform(-1, 1, m) * np.exp(-tt / 0.36)
        ir[int(SR * pre):, ch] = lowpass(noise, 6000, 1)
    return ir / np.sqrt(np.sum(ir ** 2, axis=0))


tracks = [koto, bass, conga_hi, conga_lo, shekere, kick, pad, hit]
dry = np.zeros((len(koto.x), 2))
wet_in = np.zeros(len(koto.x))
for tr in tracks:
    sig = tr.x * tr.gain
    lg, rg = np.cos((tr.pan + 1) * np.pi / 4), np.sin((tr.pan + 1) * np.pi / 4)   # constant-power pan
    dry[:, 0] += sig * lg
    dry[:, 1] += sig * rg
    wet_in += sig * tr.send
ir = reverb_ir()
wet = np.stack([fftconvolve(wet_in, ir[:, ch])[:len(wet_in)] for ch in range(2)], axis=1)
mix = dry + 0.55 * wet
mix = mix[:N]
mix = highpass(mix.T, 28).T                      # clear sub rumble
fade = np.ones(N)
fade[-int(SR * 1.6):] = np.linspace(1, 0, int(SR * 1.6)) ** 2
fade[:int(SR * 0.05)] = np.linspace(0, 1, int(SR * 0.05))
mix *= fade[:, None]
mix = np.tanh(1.2 * mix / np.max(np.abs(mix))) / np.tanh(1.2) * 0.84   # gentle soft-clip; loudness set at mux

out = sys.argv[1] if len(sys.argv) > 1 else 'out/score.wav'
from scipy.io import wavfile
wavfile.write(out, SR, (mix * 32767).astype(np.int16))
print(f'wrote {out}: {N / SR:.1f} s')
