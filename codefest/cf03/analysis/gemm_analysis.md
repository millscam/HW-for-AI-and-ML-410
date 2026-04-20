# GEMM Kernel Analysis

## (a) Why the naive kernel is memory-bound
(a) The naive kernel is memory-bound because every thread independently reads its own slice of A and B with no data sharing — other threads doing the same work redundantly. The L2 cache softens the blow at 512³, but warp schedulers are still stalling 82% of the time on L2 latency (18% issue slots busy despite 96% occupancy).

## (b) How tiling cuts DRAM traffic

(b) Tiling fixes this by having the whole thread block cooperatively load one tile of A and B into shared memory together. Each element crosses the global bus once and gets reused 8× from shared mem — 8× fewer global memory transactions in theory.

## (c) Did tiling actually help — and if not, why?

(c) The tiling barely helped here (1.5%). The reason being the GPU's 4 MB L2 cache fitting the entire 3 MB working set, so the naive kernel's redundant reads were already cheap. The remaining bottleneck is the tile size itself — 8×8 = 64 threads = only 2 warps per block, which isn't enough to hide L2 latency. A 32×32 tile with register blocking would be the right next step.






