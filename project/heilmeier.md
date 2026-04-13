# Heilmeier draft
I am working with a sign-language gesture-recognition setup that uses a CNN and an RNN after frames are prepared. Repo: https://github.com/hthuwal/sign-language-gesture-recognition

I am still a little nervous about how much detail the GitHub project gives, and I had also looked at YOLO as a “safer” image-processing-style backup.

## 1. What are you trying to do? Articulate your objectives using absolutely no jargon.

What I wrote first: I want to build or design a chiplet accelerator that speeds up the heavy math in that kind of system—convolution and related image-style processing—without relying on a big CPU or GPU to do the worst work.

After looking at the profiling, I do still plan on attempting to accelerate the CNN RNN heavy math part of the algorithm, but I would also like to build the accelerator to potentially help with preprocessing, since my algorithm seems to have a lot of wall time when it takes my colored image frames and makes them gray.


## 2. How is it done today, and what are the limits of current practice?

What I wrote first: Usually, CNN and RNN algorithms work best on large GPUs, but good GPUs are expensive and power hungry, and a normal CPU struggles to keep up with CNN and RNN demand.

After looking at my profiling, it seems my algorithm has been broken up into 3 phases (preprocessing, CNN, and RNN)

PreProcessing has a current wall time of 22s over 10 runs and 880 decoded frames, the roofline showed at 1080x1920, modeled 45.6M bytes and 43.5M int-ops per frame, and an arithmetic intensity of 0.95 ops/byte and scaling by frame count against the summed decode+OpenCV hotspot times gives ~4.3 Gop/s achieved and ~4.5 GB/s implied traffic, this phase is memory-bound.

CNN has a current wall ~1.02 s for batch 4 and 10 timed repeats—TensorFlow 1 `Session.run` on a minimal frozen graph (global-mean → dense → softmax) plus JPEG decode/resize as in `predict_spatial.py`; cProfile is dominated by `TF_SessionRun_wrapper`.

RNN has a current wall of ~9.6 s for 10× one-epoch `model.fit` at batch 8—Keras LSTM(256)+Dense(softmax) on synthetic pickle data with shapes like `get_network_wide` (201×64 features, 64 classes). Time concentrates in `TFE_Py_Execute` (training, including LSTM backward)

I still expect the largest chiplet upside on the CNN+RNN tensor path—conv dataflow and reuse, fusion, narrow precision, LSTM as batched GEMM-like work with on-chip state and overlap—while preprocess stays a separate, bandwidth-heavy stage with the only fully quantified AI in the current artifacts.

## 3. What is new in your approach, and why do you think it will be successful?

What I wrote first: The new part is an accelerator chiplet aimed at convolution (and related dense tensor ops) in the per-frame network, and matrix-style operations inside the RNN/LSTM cells over the sequence, because those ops are predictable at the tensor level. It can succeed if the design feeds the compute array enough bandwidth and reuse so processing elements stay busy, and if I measure improvement on a fixed scale—fixed frame size, sequence length, and a chosen CNN+RNN configuration.

I am going to try to tackle the phase 1 preprocessing of the algorithm first with the chiplet: fused per-frame segmentation and grayscale with on-chip buffering or wide internal SRAM bandwidth so I am not writing every intermediate buffer back to DRAM each pass—because that is where project_profile.txt says the seconds went. The roofline still says there is large headroom (order about 25x just to hit the about 49 GFLOP/s memory-ridge envelope at this AI). For a notional 512 GFLOP/s engine at AI about 0.95, I need on the order of about 536 GB/s, of effective operand delivery to avoid being interface-bound.

So success still means what I said before, PEs stay busy, and I measure on fixed frame size and sequence—but the near-term proof is: same 880-frame-style run, preprocess wall time drops, and bitwise_and, inRange, and read stop owning the profile; then I'll decide how much chiplet area moves to CNN/RNN using Phase 2/3 data.
