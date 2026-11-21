"""IMA ADPCM as the stick uses it (firmware/mantiza-hands/audio.cpp): low nibble first, state carried in each packet.

The encoder mirrors the firmware and the decoder mirrors ios/Mantiza/Board/StickAudio.swift, so this file also
makes the reference vectors for the app's tests.
"""
import struct

STEPS = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97,
    107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
    4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
    22385, 24623, 27086, 29794, 32767]
INDEX_ADJUST = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
HEADER = 6


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def encode_packet(seq, samples, predictor=0, index=0):
    """One packet (header + ADPCM) and the state after it; samples must have an even length."""
    out = bytearray(struct.pack("<HhBB", seq, predictor, index, 0))
    codes = []
    for s in samples:
        step = STEPS[index]
        diff = s - predictor
        code = 0
        if diff < 0:
            code, diff = 8, -diff
        delta = step >> 3
        if diff >= step:
            code |= 4; diff -= step; delta += step
        if diff >= step >> 1:
            code |= 2; diff -= step >> 1; delta += step >> 1
        if diff >= step >> 2:
            code |= 1; delta += step >> 2
        predictor = _clamp(predictor - delta if code & 8 else predictor + delta, -32768, 32767)
        index = _clamp(index + INDEX_ADJUST[code], 0, 88)
        codes.append(code)
    for i in range(0, len(codes), 2):
        out.append(codes[i] | codes[i + 1] << 4)
    return bytes(out), predictor, index


def decode_packet(packet):
    """(seq, samples) from one plain packet."""
    seq, predictor, index, _ = struct.unpack_from("<HhBB", packet)
    samples = []
    for byte in packet[HEADER:]:
        for code in (byte & 15, byte >> 4):
            step = STEPS[index]
            delta = step >> 3
            if code & 4:
                delta += step
            if code & 2:
                delta += step >> 1
            if code & 1:
                delta += step >> 2
            predictor = _clamp(predictor - delta if code & 8 else predictor + delta, -32768, 32767)
            index = _clamp(index + INDEX_ADJUST[code], 0, 88)
            samples.append(predictor)
    return seq, samples
