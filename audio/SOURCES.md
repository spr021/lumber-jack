# SFX sources

## Chop (`chop_1.wav`, `chop_2.wav`)

The user's two Adobe Firefly renders ("cutting tree with axe", variations 3
and 4), used whole with silence cut from both ends — one variant per file,
played in weighted-random order (75% switch / 25% repeat, so it feels
unordered but never sticks on one sample):

- `chop_1.wav` — variation 3 (single whack)
- `chop_2.wav` — variation 4 (compound triple whack with its ring)

Rebuild from the originals (in `~/Downloads/Firefly_audio_cutting_tree_
with_axe_variation{3,4}.wav`):

    ffmpeg -i Firefly_audio_cutting_tree_with_axe_variation3.wav \
        -ac 1 -ar 44100 -sample_fmt s16 /tmp/chop3.wav
    ffmpeg -i Firefly_audio_cutting_tree_with_axe_variation4.wav \
        -ac 1 -ar 44100 -sample_fmt s16 /tmp/chop4.wav
    python3 -I tools/make_sfx.py --trim /tmp/chop3.wav /tmp/chop4.wav

## Game over (`game_over.wav`)

Fully synthesized original death tune (no existing melody copied): a hopeful
hop up (C5-E5-G5), a comic chromatic slide (B4-Bb4-A4-Ab4) falling to G4,
then a low "da-dum" (G3-C3). Voice is a softened square with a sub-octave
square underneath; trailing silence is cut automatically. Regenerate:

    python3 -I tools/make_sfx.py
