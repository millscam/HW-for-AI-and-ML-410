# M3 Plan — `synth_top` (Option A)

Reference run: `openlane/runs/RUN_2026-05-15_06-48-24`.

I will increase the speed to 13ns to use the headroom from the +8.6 slack, this will hopefully bring the fps into the 40-50 range and speed up past the baseline which is currently at 40fps already :( .
I do plan on trying to fix the max-fanout DRV violation, I will add a fanout maximum constraint to my config file in hopes to report 0 DRV violations.
My Stdcell area was 5860.62 which was about 42 percent of the core utilization, so I dont need to increase the area for M3 to work properly. BUUUUT I can add a second pixel lane so I can process double the Pix/Cycle and increase the fps hopefully while staying in budget.





