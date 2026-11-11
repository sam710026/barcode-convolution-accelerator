# Architecture

This description refers to the exact submitted [core](../01_RTL/core.v), SHA256
`09254f473499f56324db772e33025df77deeca484d2af1323059325f79878547`.
Requirements come from the [assignment](spec/assignment.pdf), pp. 3–8,
and [TA notes](spec/ta_notes.pdf), pp. 6–25.

## Transaction and configuration

The core accepts MSB-first image/weight bytes through a 32-bit rising-edge
ready/valid handshake. Image words serialize into four SRAM writes, so the
input interface does not sustain one word per cycle. Output compute throughput
is a separate property.

While serializing pixels, the decoder shifts their LSBs into a 46-bit window.
It compares complete Start C + K + W + Stop structures against six supported
combinations, K ∈ {3,4,5}, W ∈ {4,8}. Nineteen rotating identity/count records
track legal horizontal origins x=0…18. Ten matching consecutive rows validate
the configuration. This is a specialized configuration detector rather than a
general-purpose Code 128 decoder.

After image reception, ports 1 and 2 simultaneously report K and W. An invalid
configuration reports zeros and finishes without convolution. A valid one
receives 9, 16 or 25 signed weights, then emits all 4096 addressed results.

## Banked storage and stripe window

Eight single-port 512 × 8 SRAM instances provide 4096 bytes total. The mapping is:

```text
bank    = x mod 8
address = 8*y + floor(x/8)
```

The scheduler visits sixteen four-column stripes, top-to-bottom within each
stripe. Eight physical bank outputs supply a row spanning the neighboring
columns. Raw bank capture precedes permutation and padding so those operations
sit after the macro-output capture boundary. Four retained 8-byte rows and a
new row form a shared 5 × 8 window for four neighboring outputs.

Sixteen prefix bytes seed the initial rows and bridge stripes. The bottom two
requests fetch the next stripe's prefix instead of image rows beyond the lower
boundary. A prime request during configuration drain begins SRAM/window setup
before weight reception ends. Coefficients map into a fixed 5 × 5 grid; the
placement gives K=4 its required one-pixel top/left and two-pixel bottom/right
zero padding.

## Weight recoding and arithmetic reuse

Unsigned 8-bit pixels multiply signed fixed-point weights. W4 arrives in bits
7:4 with bits 3:0 zero (Q1.3); W8 uses the complete byte (Q1.7). Retaining the
raw byte gives both formats a common 1/128 scale.

At load time, each signed raw coefficient is decomposed as:

```text
w = 16*h + l
h = signed(high nibble) + bit3
l = signed(low nibble)
```

Each component becomes two radix-4 signed digits in {−2,−1,0,1,2}. Digit codes
select x, 2x and sign through masks/shifts/inversion. Four `hw3_fused_heap`
instances fuse these terms into carry-save reductions, each with 25 tap slots.

| Mode | Heap scheduling | Steady-state output rate |
| --- | --- | --- |
| Any K / W4 | High component only, shifted by four | 4 pixels/cycle |
| K=3 / W8 | Nine high and nine low components occupy 18 slots together | 4 pixels/cycle |
| K=4 or 5 / W8 | Alternate low/high tokens, retaining a carry-save feedback pair | 4 pixels/2 cycles |

The heap registers after compressor levels 2/4/7/10/12. A subsequent merge
applies the coefficient-sign correction and, in two-phase modes, combines
low/high contributions. The final carry-propagate addition is split into
11-bit and 10-bit portions. Valid, address and phase tags follow payload data;
five heap cuts are only part of the end-to-end pipeline.

One's-complement negative-digit payloads require a correction term. The core
computes and freezes that correction after coefficient loading instead of
putting repeated correction arithmetic in the per-pixel path. All carry-save
operations use a 21-bit modulo representation; the worst signed true sum is
bounded by 25 × 255 × 128 = 816000, within the signed 21-bit range.

## Numerical and output behavior

The golden-compatible operation is unflipped-kernel cross-correlation:

```text
S[y,x] = sum(image[y+ky-p, x+kx-p] * signed(weight_byte[ky*K+kx]))
p = floor((K-1)/2); pixels outside the image are zero
output = clamp(round_half_away_from_zero(S/128), 0, 255)
```

The RTL directly clamps negative totals to zero; for nonnegative totals it rounds
using bit 6 and saturates overflow. This yields the stated rounded-and-clamped
output without explicitly rounding negative magnitudes. Partial products and
partial sums are not individually rounded or saturated.

Four valids commit adjacent addresses base…base+3. The base is
`64*row + 4*stripe`; output is stripe ordered. Finish may coincide with the final
four outputs and remains asserted until reset.

## Reset and technology hooks

A two-flop release chain asynchronously clears and synchronizes internal reset
deassertion. External outputs clear asynchronously. Most datapath payloads have
no reset and become observable only with valid tags after initialization.

`cap_ff8` uses behavioral registers during RTL simulation and `DFFHQX8` under
`SYNTHESIS`. `csa_fa` uses Boolean full-adder equations during RTL simulation
and `ADDFX1` under synthesis. The preserved synthesis script protects capture
cells and applies size-only protection to heap adder cells by default.

These technology selections express design intent; matching mapped reports,
recovery/removal checks, setup/hold timing and timed GLS are required to establish
their physical result. See [performance](PERFORMANCE.md).
